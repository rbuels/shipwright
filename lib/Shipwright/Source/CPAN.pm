package Shipwright::Source::CPAN;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Source::Compressed;
use CPAN;
use Data::Dumper;
use File::Temp qw/tempdir/;
use File::Spec;
use File::Slurp;
use UNIVERSAL::require;
use CPAN::DistnameInfo;

use base qw/Shipwright::Source::Base/;

my $cpan_dir = tempdir( CLEANUP => 0 );
unshift @INC, $cpan_dir;

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    CPAN::Config->use;

    mkdir File::Spec->catfile( $cpan_dir, 'CPAN' );
    my $config_file = File::Spec->catfile( $cpan_dir, 'CPAN', 'MyConfig.pm' );

    unless ( -f $config_file ) {
        $CPAN::Config->{cpan_home} = File::Spec->catfile($cpan_dir);
        $CPAN::Config->{build_dir} = File::Spec->catfile( $cpan_dir, 'build' );
        $CPAN::Config->{histfile} =
          File::Spec->catfile( $cpan_dir, 'histfile' );
        $CPAN::Config->{keep_source_where} =
          File::Spec->catfile( $cpan_dir, 'sources' );
        $CPAN::Config->{prefs_dir} = File::Spec->catfile( $cpan_dir, 'prefs' );
        $CPAN::Config->{prerequisites_policy} = 'follow';
        $CPAN::Config->{urllist}              = [];
        write_file( $config_file,
            Data::Dumper->Dump( [$CPAN::Config], ['$CPAN::Config'] ) );

    }
    require CPAN::MyConfig;
    return $self;
}

=head2 run

=cut

sub run {
    my $self = shift;
    $self->log->info( "prepare to run source: " . $self->source );
    if ( $self->_run ) {
        my $compressed =
          Shipwright::Source::Compressed->new( %$self, _no_update_url => 1 );
        $compressed->run(@_);
    }
}

sub _run {
    my $self = shift;
    return if $self->source eq 'perl';    # don't expand perl itself;

    my ( $source, $distribution );

    if ( $self->source =~ /\.tar\.gz$/ ) {

        # it's a disribution
        $distribution = CPAN::Shell->expand( 'Distribution', $self->source );

        unless ($distribution) {
            $self->log->warn( "can't find "
                  . $self->source
                  . ' on CPAN, assuming you will manually fix it. good luck!' );
            return;
        }

        # distribution source isn't good for shipwright, convert it to a
        # module name it contains
        $self->source( ( $distribution->containsmods )[0] );

        $source = $distribution->{ID};
    }
    else {

        # it's a module
        my $module = CPAN::Shell->expand( 'Module', $self->source );

        unless ($module) {
            $self->log->warn( "can't find "
                  . $self->source
                  . ' on CPAN, assuming you will manually fix it. good luck!' );
            return;
        }

        $source = $module->cpan_file;

        $distribution = $module->distribution;

        my $info = CPAN::DistnameInfo->new( $module->cpan_file );

        if ( $self->version ) {
            my $latest_version = $info->version;
            my $version        = $self->version;
            if ( $latest_version =~ /^v/ && $version !~ /^v/ ) {
                $version = 'v' . $version;
            }
            $distribution->{ID} =~ s/$latest_version/$version/;
            $source             =~ s/$latest_version/$version/;
        }
    }

    my $name = CPAN::DistnameInfo->new( $distribution->{ID} )->dist;

    $distribution->get;

    $self->name( 'cpan-' . $name );
    $self->_update_map( $self->source, 'cpan-' . $name );

    $self->source(
        File::Spec->catfile(
            $CPAN::Config->{keep_source_where},
            'authors', 'id', $source
        )
    );
    return 1;
}

1;

__END__

=head1 NAME

Shipwright::Source::CPAN - CPAN source


=head1 DESCRIPTION


=head1 DEPENDENCIES

None.


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
