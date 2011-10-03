package Amling::Git::GRD::Command::Edit;

use strict;
use warnings;

use Amling::Git::GRD::Command;
use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Utils;

use base 'Amling::Git::GRD::Command::Simple';

sub name
{
    return "edit";
}

sub args
{
    return 0;
}

sub execute_simple
{
    print "Edit requested, dropping into shell...\n";
    Amling::Git::GRD::Utils::run_shell(1, 0, 0);
    print "Edit complete, continuing...\n";
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
