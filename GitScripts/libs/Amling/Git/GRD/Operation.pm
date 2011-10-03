package Amling::Git::GRD::Operation;

use strict;
use warnings;

my @handlers;

sub add_operation
{
    my $pfn = shift;

    push @handlers, $pfn;
}

sub parse
{
    my $s = shift;

    for my $handler (@handlers)
    {
        my @ret = $handler->($s);

        if(@ret)
        {
            return (1, @ret);
        }
    }

    return (0);
}

require Amling::Git::GRD::Operation::MLinear;

1;
