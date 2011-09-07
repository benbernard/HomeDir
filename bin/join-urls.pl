#!/usr/bin/perl

$| = 1;

use strict;
use warnings;

TOP:
while(<>)
{
    chomp;
    while(/https?:\/\/[^ ]*$/)
    {
        my $l2 = <>;
        if(!$l2)
        {
            print $_ . "\n";
            last TOP;
        }
        chomp $l2;
        if(!$l2)
        {
            print $_ . "\n\n";
            next TOP;
        }
        # /^https?:\/\// for URL lists
        # /^Requester: / for CU
        if($l2 =~ /^https?:\/\// || $l2 =~ /^Requester: /)
        {
            print $_ . "\n";
            $_ = "";
        }
        $_ .= $l2;
    }
    print $_ . "\n";
}
