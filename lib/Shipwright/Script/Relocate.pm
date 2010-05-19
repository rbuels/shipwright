package Shipwright::Script::Relocate;

use strict;
use warnings;
use Shipwright::Util;

use base qw/App::CLI::Command Shipwright::Script/;

__PACKAGE__->mk_accessors('as');

sub options {
    ( 'as=s' => 'as', );
}

use Shipwright;

sub run {
    my $self = shift;
    my ( $name, $new_source ) = @_;

    confess_or_die "need name arg"   unless $name;
    confess_or_die "need source arg" unless $new_source;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        source     => $new_source,
    );

    my $source   = $shipwright->backend->source;
    my $branches = $shipwright->backend->branches;

    # die if the specified branch doesn't exist
    if ( $branches && $self->as ) {
        confess_or_die "$name doesn't have branch "
          . $self->as
          . ". please use import cmd instead"
          unless grep { $_ eq $self->as } @{ $branches->{$name} || [] };
    }

    if ( exists $source->{$name} ) {
        if (
            (
                ref $source->{$name}
                  && $source->{$name}{ $self->as || $branches->{$name}[0] } eq
                  $new_source
            )
            || $source->{$name} eq $new_source
          )
        {
            $self->log->fatal(
                "the new source is the same as old source, won't update"
            );
        }
        else {
            if ( ref $source->{$name} ) {
                $source->{$name} = {
                    %{ $source->{$name} },
                    $self->as || $branches->{$name}[0] => $new_source
                };
            }
            else {
                $source->{$name} = $new_source;
            }

            $shipwright->backend->source($source);
            $self->log->fatal( "relocated $name to $new_source with success" );
        }
    }
    else {
        $self->log->fatal( "haven't found $name in source.yml, won't relocate" );
    }

}

1;

__END__

=head1 NAME

Shipwright::Script::Relocate - Relocate source of a dist(not cpan)

=head1 SYNOPSIS

 relocate NAME SOURCE

=head1 OPTIONS

   -r [--repository] REPOSITORY    : specify the repository of our project
   -l [--log-level] LOGLEVEL       : specify the log level
   --log-file FILENAME             : specify the log file
                                     (info, debug, warn, error, or fatal)
   NAME                            : sepecify the dist name
   SOURCE                          : specify the new source


=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

