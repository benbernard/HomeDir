package Amling::Git::GRD::Command::Pick;

use strict;
use warnings;

use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Command;
use Amling::Git::GRD::Utils;
use Amling::Git::Utils;

use base 'Amling::Git::GRD::Command::Simple';

# ugh, should probably get tetchy somewhere if we're asked to handle a multi-parent commit

sub extended_handler
{
    my $s = shift;

    my ($commit, $msg);
    if($s =~ /^pick ([^ ]+) ([^ ].*)$/)
    {
        $commit = $1;
        $msg = $2;
    }
    else
    {
        return undef;
    }

    return __PACKAGE__->new($commit, Amling::Git::GRD::Utils::unescape_msg($msg));
}

sub name
{
    return "pick";
}

sub args
{
    return 1;
}

sub execute_simple
{
    my $self = shift;
    my $ctx = shift;
    my $commit = shift;
    my $msg = shift;

    # if $commit's parent is us we're "picking" a change one down the line, we
    # can just fast-forward to it
    if(Amling::Git::Utils::convert_commitlike("$commit^") eq Amling::Git::Utils::convert_commitlike("HEAD"))
    {
        print "Fast-forward cherry-picking $commit...\n";
        Amling::Git::GRD::Utils::run("git", "reset", "--hard", $commit);
    }
    else
    {
        if(!Amling::Git::GRD::Utils::run("git", "cherry-pick", $commit))
        {
            if(Amling::Git::Utils::is_clean())
            {
                print "git cherry-pick of $commit blew chunks, but we're clean, assuming skip...\n";
                return;
            }

            print "git cherry-pick of $commit blew chunks, please clean it up (get correct version into index)...\n";
            Amling::Git::GRD::Utils::run_shell(1, 1, 0);
            print "Continuing...\n";

            if(Amling::Git::Utils::is_clean())
            {
                print "Shell left clean, assuming skip...\n";
                return;
            }

            if(defined($msg))
            {
                # allow edit since we would normally
                Amling::Git::GRD::Utils::run("git", "commit", "-m", $msg, "-e") || die "Cannot commit?";

                # no further amendment required
                $msg = undef;
            }
            else
            {
                Amling::Git::GRD::Utils::run("git", "commit", "-c", $commit) || die "Cannot commit?";
            }
        }
    }

    if(defined($msg))
    {
        Amling::Git::GRD::Utils::run("git", "commit", "--amend", "-m", $msg) || die "Cannot amend?";
    }
}

sub str_simple
{
    my $self = shift;
    my $commit = shift;
    my $msg = shift;

    return "pick $commit" . (defined($msg) ? " (amended message)" : "");
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });
Amling::Git::GRD::Command::add_command(\&extended_handler);

1;
