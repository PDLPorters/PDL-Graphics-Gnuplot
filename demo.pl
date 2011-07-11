#!/usr/bin/perl
use strict;
use warnings;
use lib 'lib';

use PDL;
use PDL::NiceSlice;
use PDL::Graphics::Gnuplot qw(plot plot3d);


use feature qw(say);

# data I use for 2D testing
my $x = sequence(21) - 10;

# data I use for 3D testing
my $th   = zeros(30)->           xlinvals( 0,          3.14159*2);
my $ph   = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);
my $x_3d = PDL::flat( cos($ph)*cos($th));
my $y_3d = PDL::flat( cos($ph)*sin($th));
my $z_3d = PDL::flat( sin($ph) * $th->ones );


#################################
# Now the tests!
#################################

# first, some very basic stuff. Testing implicit domains, multiple curves in
# arguments, packed in piddles, etc
plot($x**2);
plot(-$x, $x**3);
plot(-$x, $x**3,
     $x,  $x**2);
plot(PDL::cat($x**2, $x**3));
plot(-$x,
     PDL::cat($x**2, $x**3));

# some more varied plotting, using the object-oriented interface
{
  my $plot = PDL::Graphics::Gnuplot->new(globalwith => 'linespoints', xmin => -10,
                                         title => 'Error bars and other things');

  $plot->plot(with => 'lines lw 4',
              y2 => 1, legend => 'a parabola',
              PDL::cat($x, $x*2, $x*3), $x**2 - 300,

              y2 => 0,
              with => 'xyerrorbars', tuplesize => 4,
              $x**2 * 10, $x**2/40, $x**2/2, # implicit domain

              {with => '', legend => 'cubic', tuplesize => 2},
              {legend => 'shifted cubic'},
              $x, PDL::cat($x**3, $x**3 - 100) );
}

# a way to control the point size
plot({cbmin => -600, cbmax => 600}, {with => 'points pointtype 7 pointsize variable palette', tuplesize => 4},
     $x**2, abs($x)/2, $x*50);

################################
# some 3d stuff
################################

# plot a sphere
plot3d( globalwith => 'points', title  => 'sphere',
        square => 1,

        {legend => 'sphere'}, $x_3d, $y_3d, $z_3d,
      );

# sphere, ellipse together
plot3d( globalwith => 'points', title  => 'sphere, ellipse',
        square => 1,

        {legend => 'sphere'}, {legend => 'ellipse'},
        $x_3d->cat($x_3d*2),
        $y_3d->cat($y_3d*2), $z_3d );



# similar, written to a png
plot3d (globalwith => 'points', title    => 'sphere, ellipse',
        square   => 1,
        hardcopy => 'spheres.png',

        {legend => 'sphere'}, {legend => 'ellipse'},
        $x_3d->cat($x_3d*2), $y_3d->cat($y_3d*2), $z_3d );


# some paraboloids plotted on an implicit 2D domain
{
  my $xy = zeros(21,21)->ndcoords - pdl(10,10);
  my $z = inner($xy, $xy);

  my $xy_half = zeros(11,11)->ndcoords;
  my $z_half = inner($xy_half, $xy_half);

  plot3d( globalwith => 'points', title  => 'gridded paraboloids',
          {legend => 'zplus'} , {legend=>'zminus'}, $z->cat(-$z),
          {legend => 'zplus2'}, $z*2);
}

# 3d, variable color, variable pointsize
{
 my $pi   = 3.14159;
 my $theta = zeros(200)->xlinvals(0, 6*$pi);
 my $z     = zeros(200)->xlinvals(0, 5);

 plot3d( title => 'double helix',

         { with => 'points pointsize variable pointtype 7 palette', tuplesize => 5,
           legend => 'spiral 1'},
         { legend => 'spiral 2' },

         # 2 sets of x, y, z:
         cos($theta)->cat(-cos($theta)),
         sin($theta)->cat(-sin($theta)),
         $z,

         # pointsize, color
         0.5 + abs(cos($theta)), sin(2*$theta) );
}

# implicit domain heat map
{
  my $xy = zeros(21,21)->ndcoords - pdl(10,10);
  plot3d(title  => 'Paraboloid heat map',
         extracmds => 'set view 0,0',
         with => 'image', inner($xy, $xy));
}

################################
# testing some error detection
################################

say STDERR 'should complain about an invalid "with":';
say STDERR "=================================";
eval( <<'EOM' );
plot(with => 'bogusstyle', $x);
EOM
print STDERR $@ if $@;
say STDERR "=================================\n\n";


say STDERR 'Gnuplot 4.4.0 gets confused about binary input. PDL::Graphics::Gnuplot should detect this and quit after a few seconds:';
say STDERR "=================================";
eval( <<'EOM' );
  my $xy = zeros(21,21)->ndcoords - pdl(10,10);
  plot3d(binary => 1,
         title  => 'Paraboloid heat map',
         extracmds => 'set view 0,0',
         with => 'image', inner($xy, $xy));
EOM
print STDERR $@ if $@;
say STDERR "=================================\n\n";
