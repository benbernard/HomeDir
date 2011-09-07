#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Data::Dumper;

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
my $TITLE = 'RatPoison Windows';
my $ratpoison_window_name;

use Ratpoison;

GetOptions(
  #'filter=s'       => \$filter,
  'windowname=s'    => \$ratpoison_window_name,
);

my $windows = Windows->new();
my $rt = Ratpoison->new();

show_buffers();

die "Curses failed, reached unreable point!";

sub show_buffers {
  $cui = Curses::UI->new();

  $win = $cui->add('window_id', 'Window');

  my ($values, $labels, $selected) = determine_values_and_labels();

  $listbox = $win->add(
    'mylistbox',  'Listbox',
    -values    => $values,
    -labels    => $labels,
    -onchange  => \&select_window,
    -title     => get_title(),
    -selected  => $selected,
    -htmltext  => 1,
    -padleft   => 0,
    -border    => 1,
    -padbottom => 1,
  );

  $listbox->focus();

  $listbox->set_binding(\&quit, "q" );
  $listbox->set_binding(\&quit, "Q" );

  $listbox->set_binding(\&show_buffer, "l" );

  $listbox->set_binding(\&show_full_help, 'h');

  add_help($win, $listbox);

  $cui->set_timer('update_windows', \&update_windows, 1);

  $cui->mainloop();
}

sub select_window {
  my $window = get_current_window();
  $windows->run_rat('select ' . $window->{'window_number'});
  update_windows();
}

sub get_current_window {
  my $selection = $listbox->get_active_value();
  my $window = $windows->get_windows()->[$selection];
  return $window;
}

sub show_buffer {
  my $window = get_current_window();
  show_text(Data::Dumper::Dumper($window),
            { -title => 'Full String for: ' . display_string($window) });
}

sub display_string {
  my $window = shift;
  return $window->{'title'};
}

sub get_title {
  return $TITLE;
}

sub determine_values_and_labels {
  my $windows = $windows->get_windows();

  my @values;
  my %labels;
  my $index = 0;
  my $selected;
  foreach my $window (@$windows) {
    push @values, $index;
    $labels{$index} = $window->{window_number} . ' ' . display_string($window);
    $selected = $index if ( $window->{'status'} eq '*' && $window->{'title'} ne 'Window List' );
    $index++;
  }

  return (\@values, \%labels, $selected);
}

my $update_count = 0;
sub update_windows {
  return if ( inside_selection_window($rt) );

  $update_count++;

  $windows->update();

  $listbox->title(get_title());

  my ($values, $labels, $selected) = determine_values_and_labels();


  my $id = $listbox->get_active_id();
  $id = $selected if ( defined $selected );

  $listbox->labels($labels);
  $listbox->values(@$values);

  # fixing bug in Curses::UI::Listbox
  if ( (scalar @$values) == 0 ) {
    $listbox->{'-values'} = [];
  }

  $listbox->{'-ypos'} = $id if ( (scalar @$values) >= $id );

  $listbox->draw(1);
}

sub inside_selection_window {
  my $rt = shift;

  my $windows = $rt->get_windows();

  foreach my $window ( values %$windows ) {
    next unless ($window->{'status'} eq '*');

    # Oh yuck!
    if ( $window->{'title'} =~ m/$ratpoison_window_name/ ) {
      return 1;
    }
    else {
      return 0;
    }
  }

  return 0;
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

  enter    - select a window in rat poison

  l        - look at the full details of a window

  q, Q     - quit window display

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

package Windows;

use Ratpoison;

sub new {
  my $class = shift;

  my $this = {
    RP => Ratpoison->new(),
  };

  bless $this, $class;
  $this->update();

  return $this;
}

sub get_windows {
  my $this = shift;
  return $this->{'WINDOWS'};
}

sub update {
  my $this = shift;
  my $windows = $this->{'RP'}->get_windows();

  my @windows;

  foreach my $key (sort { $windows->{$a}->{'window_number'} <=> $windows->{$b}->{'window_number'} } keys %$windows ) {
    if ( $windows->{$key}->{'is_displayed'} ) {
      push @windows, $windows->{$key};
    }
  }

  $this->{'WINDOWS'} = \@windows,
}

sub run_rat {
  my $this = shift;
  $this->{'RP'}->run_rat(@_);
}
