package Shipwright::Script::Rename;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;
use File::Spec;
use Shipwright::Util;

sub run {
    my $self = shift;

    my ( $name, $new_name ) = @_;

    die "need name arg\n" unless $name;
    die "need new-name arg\n" unless $new_name;

    die "invalid new-name: $new_name, should only contain - and alphanumeric\n"
      unless $new_name =~ /^[-\w]+$/;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
    );

    my $order = $shipwright->backend->order;

    die "no such dist: $name\n" unless grep { $_ eq $name } @$order;

    $shipwright->backend->move(
        path     => "dists/$name",
        new_path => "dists/$new_name",
    );
    $shipwright->backend->move(
        path     => "scripts/$name",
        new_path => "scripts/$new_name",
    );

    # update order.yml
    @$order = map { $_ eq $name ? $new_name : $_ } @$order;
    $shipwright->backend->order($order);

    # update map.yml
    my $map = $shipwright->backend->map || {};
    for ( keys %$map ) {
        $map->{$_} = $new_name if $map->{$_} eq $name;
    }
    $shipwright->backend->map($map);

    # update version.yml, source.yml and flags.yml
    my $version = $shipwright->backend->version || {};
    my $source  = $shipwright->backend->source  || {};
    my $flags   = $shipwright->backend->flags   || {};

    for my $hashref ( $source, $flags, $version ) {
        for ( keys %$hashref ) {
            if ( $_ eq $name ) {
                $hashref->{$new_name} = delete $hashref->{$_};
                last;
            }
        }
    }

    $shipwright->backend->version($version);
    $shipwright->backend->source($source);
    $shipwright->backend->flags($flags);

    print "renamed $name to $new_name with success\n";
}

1;

__END__

=head1 NAME

Shipwright::Script::Rename - Rename a dist

=head1 SYNOPSIS

  shipwright rename NAME NEWNAME          rename a dist

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
