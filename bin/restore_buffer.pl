#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use BufferRing;

use Getopt::Long;

my $buffer_num;
GetOptions(
  'buffer=s' => \$buffer_num,
);

my $ring  = BufferRing->new();
my $found = 0;

my $buffers = $ring->get_buffers();
my $size    = scalar @$buffers;

my $buffer = $ring->get_buffers()->[$size - $buffer_num - 1];
if ( $buffer ) {
  $buffer->make_current_selection();
  exit 0;
}
else {
  exit 1;
}

