package Ratpoison;

use strict;
use warnings;

use IPC::Open3;
use Data::Dumper;

my $RATPOISON = '/usr/bin/ratpoison';

sub new {
  my $class   = shift;
  my $display = shift || $ENV{'DISPLAY'};

  my $this = {
    DISPLAY => $display,
  };

  bless $this, $class;
  return $this;
};

sub run_rat {
  my $this    = shift;
  my $command = shift;

  local $ENV{'DISPLAY'};
  $ENV{'DISPLAY'} = $this->get_display();

  print "Running $RATPOISON -c $command\n" if ( $ENV{'RAT_DEBUG'} );

  my @output = `$RATPOISON -c '$command'`;

  if ( $? ) {
    die "Ratpoison command for $command failed! " . join('', @output);
  }

  chomp @output;
  print "output: @output\n" if ( $ENV{'RAT_DEBUG'} );

  return \@output;
}

sub get_display {
  my $this = shift;
  return $this->{'DISPLAY'};
}

sub get_windows {
  my $this       = shift;
  my $window_key = shift || 'window_number';

  my $specs  = $this->run_rat("windows \%a\036\%c\036\%f\036\%g\036\%h\036\%H\036\%i\036\%p\036\%l\036\%M\036\%n\036\%s\036\%S\036\%t\036\%T\036\%w\036\%W\036\%x");

  my $windows = {};
  foreach my $spec (@$specs) {
    my ($appname,
        $class,
        $frame,
        $gravity,
        $height,
        $height_inc,
        $windowid,
        $pid,
        $last_access_number,
        $max_size,
        $window_number,
        $status,
        $screen_number,
        $title,
        $transient,
        $width,
        $width_inc,
        $xine_screen) = split("\036", $spec);

    my $window = {
        appname            => trim($appname),
        class              => trim($class),
        frame              => trim($frame),
        gravity            => trim($gravity),
        height             => trim($height),
        height_inc         => trim($height_inc),
        is_displayed       => ($frame ne ''),
        last_access_number => trim($last_access_number),
        max_size           => trim($max_size),
        pid                => trim($pid),
        screen_number      => trim($screen_number),
        status             => trim($status),
        title              => trim($title),
        transient          => trim($transient),
        width              => trim($width),
        width_inc          => trim($width_inc),
        window_number      => trim($window_number),
        windowid           => trim($windowid),
        xine_screen        => trim($xine_screen),
    };

    $windows->{$window->{$window_key}} = $window;
  }

  return $windows;

=head

              %a by the application name (resource name),
              %c by the resource class,
              %f by the frame number,
              %g by the gravity of the window,
              %h by the height of the window,
              %H by the unit to resize the window vertically (height_inc)
              %i by the X Window ID,
              %p by the process ID,
              %l by the last access number,
              %M by the string Maxsize, if it specifies a maximum size,
              %n by the window number,
              %s by window status (* is active window, + would  be  chosen  by
                                   other, - otherwise)
              %S by the screen number
              %t by the window name (see set winname),
              %T by the string Transient, if it is a transient window
              %w by the width of the window
              %W by the unit to resize the window horizontally (width_inc)
              %x by the xine screen number and
=cut
}

sub trim {
  my $string = shift;
  $string =~ m/^\s*(.*)\s*$/;
  return $1;
}

sub get_screen_frames {
  my $this = shift;
  $this->get_frame_output('sfdump');
}

sub get_frame_output {
  my $this    = shift;
  my $command = shift;

  my $output = $this->run_rat($command);
  die "Unparsable multiline ouput from $command!" if ( @$output > 1 );

  my $sfdump = $output->[0];
  my @frame_specs = split(',', $sfdump);

  my $frames  = {};
  my $windows = $this->get_windows('windowid');

  foreach my $frame_spec ( @frame_specs ) {
   my $frame = $this->parse_frame($frame_spec);
    $frame->{'window_data'} = $windows->{$frame->{'window'}};
    $frames->{$frame->{'number'}} = $frame;
  }

  return $frames;
}

sub select {
  my $this     = shift;
  my $selector = shift;
  my $out = $this->run_rat("select $selector");
  return $out;
}

sub title {
  my $this  = shift;
  my $title = shift;
  return $this->run_rat("title $title");
}

sub fselect {
  my $this     = shift;
  my $selector = shift;
  my $out = $this->run_rat("fselect $selector");
  return $out;
}

sub number {
  my $this     = shift;
  my $selector = shift;
  my $out =  $this->run_rat("number $selector");
  return $out;
}

sub parse_frame {
  my $this       = shift;
  my $frame_spec = shift;

  my $frame = {};

  $frame_spec =~ s/\)\s*(\d+)?$//;
  $frame->{'screen_number'} = $1 if ( defined $1 );

  $frame_spec =~ s/^\(frame\s*//;

  while ( $frame_spec ) {
    $frame_spec =~ s/^\s*:(\S+)\s*(\S+)\s*//;
    $frame->{$1} = $2;
  }

  return $frame;
}

sub get_frames {
  my $this = shift;
  return $this->get_frame_output('fdump');
}

sub get_env {
  my $this     = shift;
  my $variable = shift;

  my $output = $this->run_rat("getenv $variable");
  return $output->[0];
}

sub set_env {
  my $this     = shift;
  my $variable = shift;
  my $value    = shift;

  $this->run_rat("setenv $variable $value");
}

sub unset_env {
  my $this     = shift;
  my $variable = shift;

  my $output = $this->run_rat("unsetenv $variable");
}

sub ratinfo {
  my $this = shift;

  my $output = $this->run_rat("ratinfo")->[0];
  my ($x, $y) = split(' ', $output);
  return $x, $y;
}

sub ratwarp {
  my $this = shift;
  my $x    = shift;
  my $y    = shift;

  my $output = $this->run_rat("ratwarp $x $y");
}

1;
