#!/apollo/bin/env -e envImprovement perl/bin/perl5.8/perl -w

# See print_usage funtion for more information on what this script does.
# Author: Ben Bernard

use warnings;
use strict;

use FindBin qw($Bin); use lib $Bin . '/perl/lib';

use BufferRing;

my $ring = BufferRing->new();

my $ratmen = '/usr/local/bin/ratmen';

my $count = 0;
my $max   = 10;

my $buffers = $ring->get_buffers();

my @menu_items;
foreach my $buffer (reverse @$buffers) {
  my $display_string = "$count " . $buffer->get_display_string();
  push @menu_items, $display_string, $count;
  $count++;

  if ( $count >= $max ) {
    last;
  }
}

open(my $cmd, '-|', $ratmen, '-p', @menu_items);
my $item = <$cmd>;
close $cmd;

if (! $item) {
  # User canceled
  exit 0;
}

chomp $item;

my $size = scalar @$buffers;
my $buffer = $buffers->[$size - $item - 1];

$buffer->make_current_selection();
