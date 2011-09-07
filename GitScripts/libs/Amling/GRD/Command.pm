package Amling::GRD::Command;

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

require Amling::GRD::Command::Branch;
require Amling::GRD::Command::BranchHead;
require Amling::GRD::Command::DetachedHead;
require Amling::GRD::Command::Edit;
require Amling::GRD::Command::FSplatter;
require Amling::GRD::Command::Fixup;
require Amling::GRD::Command::Load;
require Amling::GRD::Command::Merge;
require Amling::GRD::Command::Pick;
require Amling::GRD::Command::Pop;
require Amling::GRD::Command::Push;
require Amling::GRD::Command::Save;
require Amling::GRD::Command::Splatter;
require Amling::GRD::Command::Squash;
# TODO: fracture, split commit by path

1;
