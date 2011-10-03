package Amling::Git::GRD::Command;

use strict;
use warnings;

my @handlers;

sub add_command
{
    my $pfn = shift;

    push @handlers, $pfn;
}

sub parse
{
    my $s = shift;

    for my $handler (@handlers)
    {
        my $ret = $handler->($s);

        if(defined($ret))
        {
            return $ret;
        }
    }

    return undef;
}

require Amling::Git::GRD::Command::Branch;
require Amling::Git::GRD::Command::BranchHead;
require Amling::Git::GRD::Command::DetachedHead;
require Amling::Git::GRD::Command::Edit;
require Amling::Git::GRD::Command::FSplatter;
require Amling::Git::GRD::Command::Fixup;
require Amling::Git::GRD::Command::Load;
require Amling::Git::GRD::Command::Merge;
require Amling::Git::GRD::Command::Pick;
require Amling::Git::GRD::Command::Pop;
require Amling::Git::GRD::Command::Push;
require Amling::Git::GRD::Command::Save;
require Amling::Git::GRD::Command::Splatter;
require Amling::Git::GRD::Command::Squash;
# TODO: fracture, split commit by path

1;
