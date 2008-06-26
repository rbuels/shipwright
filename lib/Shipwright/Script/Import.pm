package Shipwright::Script::Import;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/comment no_follow build_script require_yml
      name test_script extra_tests overwrite min_perl_version skip version/
);

use Shipwright;
use File::Spec;
use Shipwright::Util;
use File::Copy qw/copy move/;
use File::Temp qw/tempdir/;
use Config;
use Hash::Merge;
use List::MoreUtils qw/uniq first_index/;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

sub options {
    (
        'm|comment=s'      => 'comment',
        'name=s'           => 'name',
        'no-follow'        => 'no_follow',
        'build-script=s'   => 'build_script',
        'require-yml=s'    => 'require_yml',
        'test-script=s'    => 'test_script',
        'extra-tests=s'    => 'extra_tests',
        'overwrite'        => 'overwrite',
        'min-perl-version' => 'min_perl_version',
        'skip=s'           => 'skip',
        'version=s'        => 'version',
    );
}

my ( %imported, $version );

sub run {
    my $self   = shift;
    my $source = shift;

    if ( $self->name && !$source ) {

        # don't have source specified, use the one in repo
        my $shipwright = Shipwright->new(
            repository => $self->repository,
        );
        my $map    = $shipwright->backend->map    || {};
        my $source_yml = $shipwright->backend->source || {};

        my $r_map = { reverse %$map };
        if ( $r_map->{ $self->name } ) {
            $source = 'cpan:' . $r_map->{ $self->name };
        }
        elsif ( $source_yml->{ $self->name } ) {
            $source = $source_yml->{$self->name};
        }

    }

    die "we need source arg\n" unless $source;

    $self->skip( { map { $_ => 1 } split /\s*,\s*/, $self->skip || '' } );


    if ( $self->name ) {
        if ( $self->name =~ /::/ ) {
            $self->log->warn("we saw '::' in the name, will treat it as '-'");
            my $name = $self->name;
            $name =~ s/::/-/g;
            $self->name($name);
        }
        if ( $self->name !~ /^[-.\w]+$/ ) {
            die qq{name can only have alphanumeric characters, "." and "-"\n};
        }
    }

    my $shipwright = Shipwright->new(
        repository       => $self->repository,
        log_level        => $self->log_level,
        log_file         => $self->log_file,
        source           => $source,
        name             => $self->name,
        follow           => !$self->no_follow,
        min_perl_version => $self->min_perl_version,
        skip             => $self->skip,
        version          => $self->version,
    );

    if ( $source ) {

        unless ( $self->overwrite ) {

            # skip already imported dists
            $shipwright->source->skip(
                Hash::Merge::merge(
                    $self->skip, $shipwright->backend->map || {}
                )
            );
        }

        Shipwright::Util::DumpFile(
            $shipwright->source->map_path,
            $shipwright->backend->map || {},
        );

        $source =
            $shipwright->source->run(
                copy => { '__require.yml' => $self->require_yml },
            );

        $version =
          Shipwright::Util::LoadFile( $shipwright->source->version_path );

        my ($name) = $source =~ m{.*/(.*)$};
        $imported{$name}++;

        my $script_dir = tempdir( CLEANUP => 1 );

        if ( my $script = $self->build_script ) {
            copy( $self->build_script,
                File::Spec->catfile( $script_dir, 'build' ) );
        }
        else {
            $self->_generate_build( $source, $script_dir, $shipwright );
        }

        unless ( $self->no_follow ) {
            $self->_import_req( $source, $shipwright );

            move(
                File::Spec->catfile( $source, '__require.yml' ),
                File::Spec->catfile( $script_dir,   'require.yml' )
            ) or die "move __require.yml failed: $!\n";
        }

        $shipwright->backend->import(
            source  => $source,
            comment => $self->comment || 'import ' . $source,
            overwrite => 1,                   # import anyway for the main dist
            version   => $version->{$name},
        );
        $shipwright->backend->import(
            source       => $source,
            comment      => 'import scripts for' . $source,
            build_script => $script_dir,
            overwrite    => 1,
        );

        # merge new map into map.yml in repo
        my $new_map =
          Shipwright::Util::LoadFile( $shipwright->source->map_path )
          || {};
        $shipwright->backend->map(
            Hash::Merge::merge( $shipwright->backend->map || {}, $new_map ) );

        my $new_url =
          Shipwright::Util::LoadFile( $shipwright->source->url_path )
          || {};
        $shipwright->backend->source(
            Hash::Merge::merge( $shipwright->backend->source || {}, $new_url )
        );

        $self->_reorder($shipwright);
    }

    # import tests
    if ( $self->extra_tests ) {
        $shipwright->backend->import(
            source       => $self->extra_tests,
            comment      => 'import extra tests',
            _extra_tests => 1,
        );
    }

    if ( $self->test_script ) {
        $shipwright->backend->test_script( source => $self->test_script );
    }

    print "imported with success\n";

}

# _import_req: import required dists for a dist

sub _import_req {
    my $self         = shift;
    my $source       = shift;
    my $shipwright   = shift;
    my $require_file = File::Spec->catfile( $source, '__require.yml' );

    my $dir = $self->_parent_dir($source);

    my $map_file = File::Spec->catfile( $dir, 'map.yml' );

    if ( -e $require_file ) {
        my $req = Shipwright::Util::LoadFile($require_file);
        my $map = {};

        if ( -e $map_file ) {
            $map = Shipwright::Util::LoadFile($map_file);

        }

        opendir my ($d), $dir;
        my @sources = readdir $d;
        close $d;

        for my $type (qw/requires recommends build_requires/) {
            for my $module ( keys %{ $req->{$type} } ) {
                my $dist = $map->{$module} || $module;
                $dist =~ s/::/-/g;

                unless ( $imported{$dist}++ ) {

                    my ($s) = grep { $_ eq $dist } @sources;
                    unless ($s) {
                        $self->log->warn(
                            "we don't have $dist in source which is for "
                              . $source );
                        next;
                    }

                    $s = File::Spec->catfile( $dir, $s );

                    $self->_import_req( $s, $shipwright );

                    my $script_dir = tempdir( CLEANUP => 1 );
                    move(
                        File::Spec->catfile( $s,          '__require.yml' ),
                        File::Spec->catfile( $script_dir, 'require.yml' )
                    ) or die "move $s/__require.yml failed: $!\n";

                    $self->_generate_build( $s, $script_dir, $shipwright );

                    $shipwright->backend->import(
                        comment   => 'deps for ' . $source,
                        source    => $s,
                        overwrite => $self->overwrite,
                        version   => $version->{$dist},
                    );
                    $shipwright->backend->import(
                        source       => $s,
                        comment      => 'import scripts for' . $s,
                        build_script => $script_dir,
                        overwrite    => $self->overwrite,
                    );
                }
            }
        }
    }

}

# _generate_build:
# automatically generate build script if not provided

sub _generate_build {
    my $self       = shift;
    my $source_dir = shift;
    my $script_dir = shift;
    my $shipwright = shift;

    chdir $source_dir;

    my @commands;
    if ( -f 'Build.PL' ) {
        print
"detected Module::Build build system; generating appropriate build script\n";
        push @commands,
          'configure: %%PERL%% Build.PL --install_base=%%INSTALL_BASE%%';
        push @commands, "make: ./Build";
        push @commands, "test: ./Build test";
        push @commands, "install: ./Build install";

        # ./Build won't work because sometimes the perl path in the shebang line
        # is just a symblic link which can't do things right
        push @commands, "clean: %%PERL%% Build realclean";
    }
    elsif ( -f 'Makefile.PL' ) {
        print
"detected ExtUtils::MakeMaker build system; generating appropriate build script\n";
        push @commands,
          'configure: %%PERL%% Makefile.PL INSTALL_BASE=%%INSTALL_BASE%%';
        push @commands, 'make: make';
        push @commands, 'test: make test';
        push @commands, "install: make install";
        push @commands, "clean: make clean";
    }
    elsif ( -f 'configure' ) {
        print
          "detected autoconf build system; generating appropriate build script\n";
        @commands = (
            'configure: ./configure --prefix=%%INSTALL_BASE%%',
            'make: make',
            'install: make install',
            'clean: make clean'
        );
    }
    else {
        my ($name) = $source_dir =~ /([-\w.]+)$/;
        print "unknown build system for this dist; you MUST manually edit\n";
        print "scripts/$name/build or provide a build.pl file or this dist\n";
        print "will not be built!\n";
        $self->log->warn("I have no idea how to build this distribution");
        # stub build file to provide the user something to go from
        push @commands,
          '# Edit this file to specify commands for building this dist.';
        push @commands,
          '# See the perldoc for Shipwright::Manual::CustomizeBuild for more';
        push @commands,
          '# info.';
        push @commands, 'make: ';
        push @commands, 'test: ';
        push @commands, 'install: ';
        push @commands, 'clean: ';
    }

    open my $fh, '>', File::Spec->catfile( $script_dir, 'build' ) or die $@;
    print $fh $_, "\n" for @commands;
    close $fh;
}

# _parent_dir: return parent dir

sub _parent_dir {
    my $self   = shift;
    my $source = shift;
    my @dirs   = File::Spec->splitdir($source);
    pop @dirs;
    return File::Spec->catfile(@dirs);
}

# _reorder:
# make some hack for order.
# move ExtUtils::MakeMaker and Module::Build to the head of cpan dists

sub _reorder {
    my $self       = shift;
    my $shipwright = shift;
    my $order      = $shipwright->backend->order;

    my $first_cpan_index = first_index { /^cpan-/ } @$order;

    unless (
        (
            $order->[$first_cpan_index] eq 'cpan-ExtUtils-MakeMaker'
            && ( ( ( first_index { $_ eq 'cpan-Module-Build' } @$order ) == -1 )
                || $order->[ $first_cpan_index + 1 ] eq 'cpan-Module-Build' )
        )
        || (
            $order->[$first_cpan_index] eq 'cpan-Module-Build'
            && (
                (
                    ( first_index { $_ eq 'cpan-ExtUtils-MakeMaker' } @$order )
                    == -1
                )
                || $order->[ $first_cpan_index + 1 ] eq
                'cpan-ExtUtils-MakeMaker'
            )
        )
      )
    {
        for my $build (qw/cpan-ExtUtils-MakeMaker cpan-Module-Build/) {
            my $index = first_index { $build eq $_ } @$order;
            next if $index == -1;    # $index == -1 if not found
            if ( $index > $first_cpan_index ) {    # not the 1st cpan dist
                splice @$order, $first_cpan_index, 0, $build;
            }
        }
    }

    @$order = uniq @$order;
    $shipwright->backend->order($order);

}

1;

__END__

=head1 NAME

Shipwright::Script::Import - import a source and its dependencies

=head1 SYNOPSIS

 import SOURCE

=head1 OPTIONS

 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level] LOGLEVEL      : specify the log level
 --log-file FILENAME            : specify the log file
 -m [--comment] COMMENT         : specify the comment
 --name NAME                    : specify the source name (only alphanumeric
                                  characters, . and -)
 --build-script FILENAME        : specify the build script
 --require-yml FILENAME         : specify the require.yml
 --no-follow                    : don't follow the dependency chain
 --extra-test FILENAME          : specify the extra test source
                                  (for --only-test when building)
 --test-script FILENAME         : specify the test script (for --only-test when
                                  building)
 --min-perl-version             : minimal perl version (default is the same as
                                  the one which runs this command)
 --overwrite                    : import dependency dists anyway even if they
                                  are already in the repository
 --version                      : specify the source's version

=head1 DESCRIPTION

The import command imports a new dist into a shipwright repository from any of
a number of supported source types (enumerated below). If a dist of the name
specified by C<--name> already exists in the repository, the old files for that
dist in F<dists/> and F<scripts/> are deleted and new ones added. This is the
recommended method for updating non-svn, svk, or CPAN dists to new versions
(see L<Shipwright::Update> for more information on the C<update> command, which
is used for updating svn, svk, and CPAN dists).

=head1 SUPPORTED SOURCE TYPES

Generally, the format is L<type:schema>; be careful, there is no blank between
type and schema, just a colon.

=over 4

=item CPAN

e.g. cpan:Jifty::DBI  cpan:File::Spec

=item File

e.g. L<file:/home/sunnavy/foo-1.23.tar.gz>
L<file:/home/sunnavy/foo-1.23.tar.bz2>
L<file:/home/sunnavy/foo-1.23.tgz>

=item Directory

e.g. L<directory:/home/sunnavy/foo-1.23>
L<dir:/home/sunnavy/foo-1.23>

=item HTTP

e.g. L<http:http://example/foo-1.23.tar.gz>

You can also omit one `http', like this:

L<http://example.com/foo-1.23.tar.gz>

F<.tgz> and F<.tar.bz2> are also supported.

=item FTP

e.g. L<ftp:ftp://example.com/foo-1.23.tar.gz>
L<ftp://example.com/foo-1.23.tar.gz>

F<.tgz> and F<.tar.bz2> are also supported.

=item SVK

e.g. L<svk://public/foo-1.23> L<svk:/local/foo-1.23>

=item SVN

e.g. L<svn:file:///home/public/foo-1.23>
L<svn:http://svn.example.com/foo-1.23>

=back
