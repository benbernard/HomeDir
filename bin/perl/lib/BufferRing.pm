package BufferRing;

use strict;
use warnings;

use Data::Dumper;

use HumanStorable qw(store_file read_file);

my $user = (getpwuid($<))[0];
my $MAX_BUFFERS = 500;
my $BUFFER_FILE = "/home/$user/.buffer_ring";
my $XCLIP = '/usr/bin/xclip';
my $NC    = '/bin/nc';

sub new {
  my $class = shift;

  my $this = {
    BUFFER_FILE => $BUFFER_FILE,
    MAX_BUFFERS => $MAX_BUFFERS,
  };

  bless $this, $class;
  
  return $this;
}

sub get_buffers {
  my $this = shift;

  return $this->{'BUFFERS'} if ( $this->{'BUFFERS'} );

  $this->update_buffers();

  return $this->{'BUFFERS'};
}

sub update_buffers {
  my $this = shift;

  my $buffers = read_file($this->get_buffer_file(), []);
  $this->{'BUFFERS'} = $buffers;
}

sub get_buffer_file {
  my $this = shift;
  return $this->{'BUFFER_FILE'};
}

sub remove_buffer {
  my $this  = shift;
  my $index = shift;

  my $buffers = $this->get_buffers();
  splice(@$buffers, $index, 1);
  $this->save();
}

sub add_buffer {
  my $this         = shift;
  my $text         = shift;

  my $buffer = Buffer->new($text);
  push @{$this->get_buffers()}, $buffer;
  $this->move_stickies_up();
  $this->trim_buffers();
  $this->save();

  return $buffer;
}

sub create_new_selection {
  my $this = shift;
  my $text = shift;

  my $buffer = Buffer->new($text);
  $buffer->make_current_selection();
  $this->update_buffers();
}

sub move_stickies_up {
  my $this = shift;

  my $buffers = $this->get_buffers();
  my $size = scalar @$buffers;

  for (my $i = $size - 2; $i >=0; $i--) {
    my $current = $buffers->[$i];

    if ( $current->is_sticky() ) {
      my $temp = $buffers->[$i+1];
      $buffers->[$i+1] = $current;
      $buffers->[$i]   = $temp;
    }
  }
}

sub save {
  my $this = shift;
  store_file($this->get_buffer_file(), $this->get_buffers());
}

sub get_max_buffers {
  my $this = shift;
  return $this->{'MAX_BUFFERS'};
}

sub trim_buffers {
  my $this = shift;
  
  my $max          = $this->get_max_buffers();
  my $buffers      = $this->get_buffers();
  my $buffers_size = scalar @$buffers;

  if ( $buffers_size > $max ) {
    my $overage = $buffers_size - $max;
    # splice(@$buffers, 0, $overage);

    while ( $overage > 0 ) {
      foreach my $i (0..$buffers_size) {
        if ( ! $buffers->[$i]->is_sticky() ) {
          splice(@$buffers, $i, $overage);
          $overage--;
          last;
        }
      }
    }
  }
}

package Buffer;

sub new {
  my $class = shift;
  my $text  = shift;

  my $this = {
    TEXT => $text,
  };

  bless $this, $class;
  return $this;
}

sub get_text {
  my $this = shift;
  return $this->{'TEXT'};
}

sub is_sticky {
  my $this = shift;
  return $this->{'STICKY'};
}

sub set_sticky {
  my $this  = shift;
  my $value = shift;

  $this->{'STICKY'} = $value;
}

sub get_display_string { 
  my $this = shift;
  my $string = ($this->is_sticky() ? '+' : '-') . ' ';

  my $text = $this->get_text();
  $text =~ s/\n/\\n/gm;
  $string .= substr($text, 0, 50);
  return $string;
}

sub make_current_selection {
  my $this = shift;

  $this->xclip('pirmary');
  $this->xclip('secondary');
  $this->xclip('clipboard');
  $this->update_mac();

  system("/usr/bin/ratpoison", "-c", "echo " . $this->get_text());
}

sub xclip {
  my $this      = shift;
  my $selection = shift;

  open(my $cmd, '|-', $XCLIP, '-i', '-selection', $selection) or die "Could not exec xclip: $!";
  print $cmd $this->get_text();
  close $cmd;
}

sub update_mac {
  my $this      = shift;
  open(my $cmd, '|-', $NC, 'localhost', '24802') or die "Could not exec nc: $!";
  print $cmd $this->get_text();
  close $cmd;
}

1;
