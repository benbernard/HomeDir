package Amling::GRD::Command::Edit;

use strict;
use warnings;

use Amling::GRD::Command;
use Amling::GRD::Command::Simple;
use Amling::GRD::Utils;

use base 'Amling::GRD::Command::Simple';

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
    Amling::GRD::Utils::run_shell(1, 0, 0);
    print "Edit complete, continuing...\n";
}

Amling::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
