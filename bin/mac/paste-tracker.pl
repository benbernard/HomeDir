#!/usr/bin/perl -w

use strict;

$ENV{'SCREENDIR'} = $ENV{'HOME'} . '/.screen';
my $temp_file = '/tmp/buffer-exchange';
my $screen_file = '/tmp/screen-exchange';

if (!(-e $screen_file)) {
  system('touch', $screen_file); # Initialize file if not present
}

my $current_contents = get_clip();
my $screen_contents = get_screen_contents();

print "Startup:\n";
print "   Screen:    $screen_contents\n";
print "   Clipboard: $current_contents\n";

my $last_screen_write = "";

system(qw(tmux set-buffer foo));

while(1) {
  my $new = get_clip();
  my $new_screen = get_screen_contents();
  if ( ($current_contents eq $new) && ($screen_contents eq $new_screen)) {
    sleep 1;
    next;
  }

  if ($current_contents ne $new) {
    print "Found change in clipboard\n";
    $current_contents = $new;

    open(my $fh, '>', $temp_file) or die "Could not open $temp_file: $!";
    print $fh $new;
    close $fh;

    $last_screen_write = $new;

    system(qw(tmux loadb), $temp_file)
  } elsif ($screen_contents ne $new_screen) {
    $screen_contents = $new_screen;

    if ($new_screen eq $last_screen_write) {
      next;
    }

    print "Found change in screen buffer\n";
    $screen_contents = $new_screen;
    open(my $cmd, '|-', 'pbcopy') or die "could not open pbpaste: $!";
    print $cmd $screen_contents;
    close $cmd;
  }
}

sub get_clip {
  return `pbpaste`;
}

sub get_screen_contents {
  open(my $fh, '-|', qw(tmux saveb -)) or die "Could not open $screen_file: $!";
  local $/;
  my $contents = <$fh>;
  close $fh;
  return $contents;
}
