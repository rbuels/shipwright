package Shipwright::Util;

use warnings;
use strict;
use Carp;
use IPC::Run3;
use File::Spec::Functions qw/catfile catdir splitpath splitdir tmpdir rel2abs/;
use Cwd qw/abs_path getcwd/;

use Shipwright;    # we need this to find where Shipwright.pm lives
use YAML::Tiny;

our ( $SHIPWRIGHT_ROOT, $SHARE_ROOT );

BEGIN {
    *Load     = *YAML::Tiny::Load;
    *Dump     = *YAML::Tiny::Dump;
    *LoadFile = *YAML::Tiny::LoadFile;
    *DumpFile = *YAML::Tiny::DumpFile;
}

=head1 LIST

=head2 YAML

=head3 Load, LoadFile, Dump, DumpFile

Load, LoadFile, Dump and DumpFile are just dropped in from L<YAML> or L<YAML::Syck>.


=head2 GENERAL HELPERS

=head3 run

a wrapper of run3 sub in IPC::Run3.

=cut

sub run {
    my $class          = shift;
    my $cmd            = shift;
    my $ignore_failure = shift;

    if ( ref $cmd eq 'CODE' ) {
        my @returns;
        if ( $ignore_failure ) {
            @returns = eval { $cmd->() };
        }
        else {
            @returns = $cmd->();
        }
        return wantarray ? @returns : $returns[0];
    }

    my $log = Log::Log4perl->get_logger('Shipwright::Util');

    my ( $out, $err );
    $log->info( "run cmd: " . join ' ', @$cmd );
    Shipwright::Util->select('null');
    run3( $cmd, undef, \$out, \$err );
    Shipwright::Util->select('stdout');

    $log->debug("run output:\n$out") if $out;
    $log->error("run err:\n$err")   if $err;

    if ($?) {
        $log->error(
            'failed to run ' . join( ' ', @$cmd ) . " with exit number $?" );
        unless ($ignore_failure) {
            $out = "\n$out" if length $out;
            $err = "\n$err" if length $err;
            my $suggest = '';
            if ( $err && $err =~ /Can't locate (\S+)\.pm in \@INC/ ) {
                my $module = $1;
                $module =~ s!/!::!g;
                $suggest = "install $module first";
            }

            my $cwd = getcwd;
            confess <<"EOF";
command failed: @$cmd
\$?: $?
cwd: $cwd
stdout was: $out
stderr was: $err
suggest: $suggest
EOF
        }

    }

    return wantarray ? ( $out, $err ) : $out;

}

=head3 select

wrapper for the select in core

=cut

my ( $null_fh, $stdout_fh, $cpan_fh, $cpan_log_path, $cpan_fh_flag );

# use $cpan_fh_flag to record if we've selected cpan_fh before, so so,
# we don't need to warn that any more.

open $null_fh, '>', '/dev/null';

$cpan_log_path = catfile( tmpdir(), 'shipwright_cpan.log');

open $cpan_fh, '>>', $cpan_log_path;
$stdout_fh = CORE::select();

sub select {
    my $self = shift;
    my $type = shift;

    if ( $type eq 'null' ) {
        CORE::select $null_fh;
    }
    elsif ( $type eq 'stdout' ) {
        CORE::select $stdout_fh;
    }
    elsif ( $type eq 'cpan' ) {
        warn "CPAN related output will be at $cpan_log_path\n"
          unless $cpan_fh_flag;
        $cpan_fh_flag = 1;
        CORE::select $cpan_fh;
    }
    else {
        confess "unknown type: $type";
    }
}

=head3 find_module

Takes perl modules name space and name of a module in the space.
Finds and returns matching module name using case insensitive search, for
example:

    Shipwright::Util->find_module('Shipwright::Backend', 'svn');
    # returns 'Shipwright::Backend::SVN'

    Shipwright::Util->find_module('Shipwright::Backend', 'git');
    # returns 'Shipwright::Backend::Git'

Returns undef if there is no module matching criteria.

=cut

sub find_module {
    my $self = shift;
    my $space = shift;
    my $name = shift;

    my @space = split /::/, $space;
    my @globs = map File::Spec->catfile($_, @space, '*.pm'), @INC;
    foreach my $glob ( @globs ) {
        foreach my $module ( map { /([^\\\/]+)\.pm$/; $1 } glob $glob ) {
            return join '::', @space, $module
                if lc $name eq lc $module;
        }
    }
    return;
}

=head2 PATHS

=head3 shipwright_root

Returns the root directory that Shipwright has been installed into.
Uses %INC to figure out where Shipwright.pm is.

=cut

sub shipwright_root {
    my $self = shift;

    unless ($SHIPWRIGHT_ROOT) {
        my $dir = ( splitpath( $INC{"Shipwright.pm"} ) )[1];
        $SHIPWRIGHT_ROOT = rel2abs($dir);
    }

    return ($SHIPWRIGHT_ROOT);
}

=head3 share_root

Returns the 'share' directory of the installed Shipwright module. This is
currently only used to store the initial files in project.

=cut

sub share_root {
    my $self = shift;

    unless ($SHARE_ROOT) {
        my @root = splitdir( $self->shipwright_root );

        if (   $root[-2] ne 'blib'
            && $root[-1] eq 'lib'
            && ( $^O !~ /MSWin/ || $root[-2] ne 'site' ) )
        {

            # so it's -Ilib in the Shipwright's source dir
            $root[-1] = 'share';
        }
        else {
            push @root, qw/auto share dist Shipwright/;
        }

        $SHARE_ROOT = catdir(@root);
    }

    return ($SHARE_ROOT);

}

=head3 user_home

return current user's home directory

=cut

sub user_home {
    return $ENV{HOME} if $ENV{HOME};

    my $home = eval { (getpwuid $<)[7] };
    if ( $@ ) {
        confess "can't find user's home, please set it by env HOME";    
    }
    else {
        return $home;
    }
}

=head3 shipwright_user_root

the user's own shipwright root where we put internal files in.
it's ~/.shipwright by default.
it can be overwritten by $ENV{SHIPWRIGHT_USER_ROOT}

=cut

sub shipwright_user_root {
    return $ENV{SHIPWRIGHT_USER_ROOT} || catdir( user_home, '.shipwright' );
}

=head3 parent_dir

return the dir's parent dir, the arg must be a dir path

=cut

sub parent_dir {
    my $self = shift;
    my $dir  = shift;
    my @dirs = splitdir($dir);
    pop @dirs;
    return catdir(@dirs);
}

1;

__END__

=head1 NAME

Shipwright::Util - Util

=head1 DESCRIPTION

=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007-2009 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

