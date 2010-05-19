package Shipwright::Script::Maintain;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/update_order update_refs graph_deps skip_recommends 
      skip_build_requires skip_requires for_dists/
);

use Shipwright;

sub options {
    (
        'graph-deps'          => 'graph_deps',
        'update-order'        => 'update_order',
        'update-refs'         => 'update_refs',
        'skip-recommends'     => 'skip_recommends',
        'skip-requires'       => 'skip_requires',
        'skip-build-requires' => 'skip_build_requires',
        'for-dists=s'         => 'for_dists',
    );
}

sub run {
    my $self = shift;

    my $shipwright = Shipwright->new( repository => $self->repository, );

    if ( $self->update_order ) {
        $shipwright->backend->update_order(
            for_dists => [ split /,\s*/, $self->for_dists || '' ],
            map { $_ => $self->$_ }
              qw/skip_requires skip_recommends skip_build_requires/,
        );
        $self->log->fatal( 'updated order with success' );
    } 
    if ($self->graph_deps)  {
        my $out = $shipwright->backend->graph_deps(
            for_dists => [ split /,\s*/, $self->for_dists || '' ],
            map { $_ => $self->$_ }
              qw/skip_requires skip_recommends skip_build_requires/,
        );
        $self->log->fatal( $out );
    }

    if ( $self->update_refs ) {
        $shipwright->backend->update_refs;
        $self->log->fatal( 'updated refs with success' );
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Maintain - Maintain a project

=head1 SYNOPSIS

 maintain --update-order

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --update-order               : update the build order
 --update-refs                : update refs( times a dist shows in all the require.yml )
 --graph-deps                 : output a graph of all the dependencies in your vessel
                                suitable for rendering by dot (http://graphviz.org) 
 --for-dists                  : limit the dists
 --skip-requires              : skip requires when finding deps
 --skip-recommends            : skip recommends when finding deps
 --skip-build-requires        : skip build requires when finding deps

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

