#!/usr/bin/perl
use strict;
use warnings;
use lib 'lib';

use PDL;
use PDL::NiceSlice;
use PDL::Gnuplot qw(plot);


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

# various ways of giving options, some multi-range stuff
plot( linespoints => 1, title => 'fanciness',
      $x, $x**2,

      {with => 'linespoints', legend => 'cubic'},
      {legend => 'shifted cubic'},
      $x, PDL::cat($x**3, $x**3 - 100),

      with => 'circles', y2 => 1, $x, $x**2 + 1, $x**2/400 );

# some more varied plotting, using the object-oriented interface
{
  my $plot = PDL::Gnuplot->new(linespoints => 1, xmin => -10,
                               title => 'fanciness');

  $plot->plot( style => 'lw 4', y2 => 1, legend => 'a parabola',
               PDL::cat($x, $x*2, $x*3), $x**2 - 300,

               y2 => 0,
               style => 'lw 1',
               with => 'xyerrorbars', extraValuesPerPoint => 2,
               $x**2 * 10, $x**2/40, $x**2/2, # implicit domain

               {with => '', legend => 'cubic', extraValuesPerPoint => 0},
               {legend => 'shifted cubic'},
               $x, PDL::cat($x**3, $x**3 - 100) );

}



################################
# some 3d stuff
################################

# plot a sphere
plot( points => 1, title  => 'sphere',
      '3d'   => 1, square => 1,

      {legend => 'sphere'}, $x_3d, $y_3d, $z_3d,
    );

# sphere, ellipse together
plot( points => 1, title  => 'sphere',
      '3d'   => 1, square => 1,

      {legend => 'sphere'}, {legend => 'ellipse'},
                             $x_3d->cat($x_3d*2),
                             $y_3d->cat($y_3d*2), $z_3d );



# similar, written to a pdf
plot(points => 1, title    => '2 spheres',
#     colormap => 1,
     '3d'     => 1,
     square   => 1, hardcopy => 'spheres.pdf',

     {legend => 'sphere'}, {legend => 'ellipse'},
     $x_3d->cat($x_3d*2), $y_3d->cat($y_3d*2), $z_3d );


# some paraboloids plotted on an implicit 2D domain
{
  my $xy = zeros(21,21)->ndcoords - pdl(10,10);
  my $z = inner($xy, $xy);

  my $xy_half = zeros(11,11)->ndcoords;
  my $z_half = inner($xy_half, $xy_half);

  plot(points => 1, title  => 'gridded paraboloids', '3d' => 1,
       {legend => 'zplus'} , {legend=>'zminus'}, $z->cat(-$z),
       {legend => 'zplus2'}, $z*2);
}
