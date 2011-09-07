#!/usr/bin/perl -w

# See print_usage funtion for more information on what this script does.
# Author: Ben Bernard

use warnings;
use strict;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use BufferRing;

use Curses;
use Curses::UI;
use File::Basename;
use File::Temp qw(tempfile);

use Data::Dumper;

use Getopt::Long;

my $cui;
my $win;
my $listbox;
my $display_count = 0;
my $TITLE = 'Buffer Ring';

system($ENV{HOME} . "/bin/autosel.pl 1>/dev/null 2>/dev/null &");

GetOptions(
  #'filter=s'       => \$filter,
);

my $ring = BufferRing->new();

print "calling show_buffers\n";
eval { 
  show_buffers();
};

die "Curses failed, reached unreable point!: $@";

sub show_buffers {
  warn "in show buffers\n";
  $cui = Curses::UI->new();

  warn "initialized!\n";

  $win = $cui->add('window_id', 'Window');

  warn "about to call determine values\n";

  my ($values, $labels) = determine_values_and_labels();

  $listbox = $win->add(
    'mylistbox',  'Listbox',
    -values    => $values,
    -labels    => $labels,
    -onchange  => \&copy_item,
    -title     => get_title(),
    -htmltext  => 1,
    -padleft   => 0,
    -border    => 1,
    -padbottom => 1,
  );

  $listbox->focus();

  $listbox->set_binding(\&quit, "q" );
  $listbox->set_binding(\&quit, "Q" );

  $listbox->set_binding(\&remove_item, "d" );
  $listbox->set_binding(\&remove_item, "x" );
  $listbox->set_binding(\&sticky_item, "s" );
  $listbox->set_binding(\&show_buffer, "l" );
  $listbox->set_binding(\&edit_buffer, "v" );

  $listbox->set_binding(\&show_full_help, 'h');

  add_help($win, $listbox);

  $cui->set_timer('update_buffers', \&update_buffers, 1);

  print "About to call mainloop\n";
  $cui->mainloop;
}

sub edit_buffer {
  my $buffer = get_current_buffer();
  my $editor = $ENV{'EDITOR'} || 'vim';

  my ($fh, $filename) = tempfile('BufferRing-XXXXX', DIR => '/var/tmp');
  print $fh $buffer->get_text();
  close $fh;

  $cui->leave_curses();

  system($editor, $filename);

  $cui->reset_curses();

  local $/;
  open(my $new_fh, '<', $filename) or die "Could not open $filename: $!";
  my $new_text = <$new_fh>;
  close $new_fh;

  $ring->create_new_selection($new_text);
  update_buffers();
}

sub get_current_buffer {
  my $selection = $listbox->get_active_value();
  my $buffer = $ring->get_buffers()->[$selection];
  return $buffer;
}

sub show_buffer {
  my $buffer = get_current_buffer();
  show_text($buffer->get_text(),
            { -title => 'Full String for: ' . $buffer->get_display_string() });
}

sub get_title {
  if (scalar @{$ring->get_buffers()} == 0 ) {
    return $TITLE;
  }

  return $TITLE . ' ' . $ring->get_buffers()->[-1]->get_display_string();
}

sub remove_item {
  my $selection = $listbox->get_active_value();

  $ring->remove_buffer($selection);
  update_buffers();
}

sub sticky_item {
  my $buffer = get_current_buffer();
  $buffer->set_sticky(not $buffer->is_sticky());
  $ring->save();
  update_buffers();
}

sub determine_values_and_labels {
  my $buffers = $ring->get_buffers();

  my $index = scalar @$buffers - 1;

  my @values;
  my %labels;
  my $count = 0;
  foreach my $buffer (reverse @$buffers) {
    push @values, $index;
    $labels{$index} = "$count " . $buffer->get_display_string();
    $index--;
    $count++;
  }

  return (\@values, \%labels);
}

my $update_count = 0;
sub update_buffers {
  $update_count++;

  $ring->update_buffers();

  $listbox->title(get_title());

  my ($values, $labels) = determine_values_and_labels();

  my $id = $listbox->get_active_id();

  $listbox->labels($labels);
  $listbox->values(@$values);

  # fixing bug in Curses::UI::Listbox
  if ( (scalar @$values) == 0 ) {
    $listbox->{'-values'} = [];
  }

  $listbox->{'-ypos'} = $id if ( (scalar @$values) >= $id );
  $listbox->draw(1);
}

sub add_help {
  my $win    = shift;
  my $parent = shift;

  $win->add(
    undef, 'Label',
    -y => -1,
    -bold => 1,
    -text => 'Hit "q" to exit, "h" for help,  Enter to copy item to X selection',
    -parent => $parent,
  );
}

sub quit {
  $cui->leave_curses();
  exit();
}

my $old_position;
sub close_details {
  my $viewer = $win->delete('mytextviewer');
  $viewer->loose_focus();

  $listbox->{'-ypos'} = $old_position;
  $listbox->clear_selection();
  $listbox->modalfocus();
}

sub show_full_help {
  my $help_text = <<TEXT;
HELP!

hit 'q' at any point to exit help

From the main selection box:

  j, k     - move up and down the main list
  up, down - also move up and down main list

  enter    - copy an buffer to the clipboard

  d, x     - remove an buffer
  s        - prevent an buffer from moving down the list
  l        - look at the full text of a buffer

  q, Q     - quit buffer display

  h        - this help screen

hit 'q' at any point to exit help
TEXT

  show_text($help_text, { -title => 'Help' } );
}

sub show_text {
  my $text       = shift;
  my $extra_args = shift || {};
  my $callback   = shift || sub { };

  my $selection = $listbox->get_active_id();
  $old_position = $selection;
  $listbox->clear_selection();
  $listbox->{'-ypos'} = -1;

  my $textviewer = $win->add( 
    'mytextviewer', 'TextViewer',
    -border    => 1,
    -parent    => $listbox,
    -padbottom => 1,
    -text      => $text,
    %$extra_args,
  );

  $textviewer->set_binding(\&close_details, "q" );
  $textviewer->set_binding(\&close_details, "Q" );
  $callback->($textviewer);

  $textviewer->modalfocus();
}

sub copy_item {
  my $buffer = get_current_buffer();
  $buffer->make_current_selection();

  update_buffers();
}
