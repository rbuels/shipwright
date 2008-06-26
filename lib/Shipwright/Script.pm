package Shipwright::Script;
use strict;
use warnings;
use App::CLI;
use base qw/App::CLI/;

=head2 alias
=cut

sub alias {
    return ( ls => 'list', 'del' => 'delete', up => 'update' );
}

=head2 global_options

=cut

sub global_options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
    );
}

=head2 prepare
=cut

sub prepare {
    my $self = shift;
    $ARGV[0] = 'help' unless @ARGV;

    if ( $ARGV[0] =~ /--?h(elp)?/i ) {
        $ARGV[0] = 'help';
    }

    my $action = $ARGV[0];

    my $cmd = $self->SUPER::prepare(@_);

    unless ( ref $cmd eq 'Shipwright::Script::Help' ) {
        if ( $cmd->repository ) {
            my $backend =
              Shipwright::Backend->new( repository => $cmd->repository );

            # this $shipwright object will do nothing, except for init logging
            my $shipwright = Shipwright->new(
                repository => $cmd->repository,
                log_level  => $cmd->log_level,
                log_file   => $cmd->log_file,
            );
            die 'invalid repository: ' . $cmd->repository
              unless $backend->check_repository( action => $action );
        }
        else {
            die "we need repository arg\n";
        }
    }
    return $cmd;
}

=head2 log
=cut

sub log {
    my $self = shift;

    # init logging is done in prepare, no need to init here, just returns logger
    return Log::Log4perl->get_logger( ref $self );
}

1;

__END__

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

