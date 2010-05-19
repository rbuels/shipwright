package Shipwright::Source::Git;

use warnings;
use strict;
use Shipwright::Util;
use File::Spec::Functions qw/catdir/;
use File::Path qw/remove_tree/;
use File::Copy::Recursive qw/rcopy/;

use base qw/Shipwright::Source::Base/;
use Cwd qw/getcwd/;

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->name( $self->just_name( $self->source ) ) unless $self->name;
    return $self;
}

=head2 run

=cut

sub run {
    my $self = shift;
    $self->log->info( "prepare to run source: " . $self->source );
    $self->_update_url( $self->name, 'git:' . $self->source );

    $self->_run();
    my $s;
    if ( $self->is_compressed ) {
        require Shipwright::Source::Compressed;
        $s = Shipwright::Source::Compressed->new( %$self, _no_update_url => 1 );
    }
    else {
        require Shipwright::Source::Directory;
        $s = Shipwright::Source::Directory->new( %$self, _no_update_url => 1 );
    }
    $s->run(@_);
}

=head2 _run

=cut

sub _run {
    my $self   = shift;
    my $source = $self->source;

    my $path = catdir( $self->download_directory, $self->name );

    my $canonical_name = $source;
    $canonical_name =~ s/:/-/g;
    $canonical_name =~ s![/\\]!_!g;

    my $cloned_path = catdir( $self->download_directory, $canonical_name );
    my @cmds;

    if ( -e $cloned_path ) {
        @cmds = sub {
            my $cwd = getcwd();
            chdir $cloned_path;
            run_cmd(
                [ $ENV{'SHIPWRIGHT_GIT'}, 'pull' ] );
            chdir $cwd;
        };
    }
    else {
        @cmds =
          ( [ $ENV{'SHIPWRIGHT_GIT'}, 'clone', $self->source, $cloned_path ] );
    }

    # work out the version stuff
    push @cmds, sub {
        my $cwd = getcwd();
        chdir $cloned_path;
        if ( $self->version ) {
            run_cmd(
                [ $ENV{'SHIPWRIGHT_GIT'}, 'checkout', $self->version ] );
        }
        else {
            my ($out) = run_cmd(
                [ $ENV{'SHIPWRIGHT_GIT'}, 'log' ] );
            if ( $out =~ /^commit\s+(\w+)/m ) {
                $self->version($1);
            }
        }
        chdir $cwd;
        remove_tree( $path ) if -e $path;
        rcopy( $cloned_path, $path ) or confess_or_die $!;
        remove_tree( catdir( $path, '.git' ) );
    };

    $self->source( $path );
    run_cmd($_) for @cmds;
}

1;

__END__

=head1 NAME

Shipwright::Source::Git - Git source


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

Copyright 2007-2010 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
