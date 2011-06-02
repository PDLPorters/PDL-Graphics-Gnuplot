#!/usr/bin/perl
use strict;
use warnings;
use lib 'lib';

use PDL;
use PDL::NiceSlice;
use PDL::Gnuplot;


use feature qw(say);

# plot a simple parabola, domain=null
{
  my $plot = PDL::Gnuplot->new(style  => 'linespoints',
                               title  => 'parabola domain=null',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( null,
               $x**2, {legend => 'parabola',
                       style => 'lw 5'}
             );
}

# plot a simple parabola, domainless
{
  my $plot = PDL::Gnuplot->new(style  => 'linespoints',
                               title  => 'parabola domainless',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x**2, {legend => 'parabola',
                       style => 'lw 5'}
             );
}

# plot parabola, cubic. domainless
{
  my $plot = PDL::Gnuplot->new(style  => 'linespoints',
                               title  => 'parabola, cubic domainless',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( PDL::cat($x**2, $x**3),
               {legend => 'parabola', style => 'lw 5'},
               {legend => 'cubic',    style => 'lw 3'}
             );
}

# plot a simple parabola
{
  my $plot = PDL::Gnuplot->new(style  => 'linespoints',
                               title  => 'parabola',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               $x**2, {legend => 'parabola',
                       style => 'lw 5'}
             );
}

# plot a simple parabola and a cubic, separate args
{
  my $plot = PDL::Gnuplot->new(style  => 'linespoints',
                               title  => 'polynomials',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               $x**2, {legend => 'parabola',
                       style => 'lw 5'},
               $x**3, {legend => 'cubic',
                       style => 'lw 5'}
             );
}

# plot a simple parabola and a cubic, single arg
{
  my $plot = PDL::Gnuplot->new(style  => 'linespoints',
                               title  => 'polynomials',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat($x**2, $x**3),
               {legend => 'parabola'},
               {legend => 'cubic', style => 'lw 5'}
             );
}

# plot a simple parabola and a cubic, separate args, with circles
{
  my $plot = PDL::Gnuplot->new(style  => 'circles',
                               title  => 'polynomials',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat($x**2, $x->abs/10), {legend => 'parabola',
                                             style => 'lw 5'},
               PDL::cat($x**3, $x->abs/10), {legend => 'cubic',
                                             style => 'lw 5'}
             );
}

# plot a simple parabola and a cubic, single arg, with circles
{
  my $plot = PDL::Gnuplot->new(style  => 'circles',
                               title  => 'polynomials',
                               xlabel => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat(PDL::cat($x**2, $x->abs/10),
                        PDL::cat($x**3, $x->abs/10)),
               {legend => 'parabola',
                style => 'lw 3'},
               {legend => 'cubic',
                style => 'lw 2'},
             );
}

# plot a simple parabola and a cubic, separate args, with colors
{
  my $plot = PDL::Gnuplot->new(style    => 'points',
                               colormap => 1,
                               title    => 'polynomials',
                               xlabel   => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat($x**2, $x->abs/10), {legend => 'parabola',
                                             style => 'lw 5'},
               PDL::cat($x**3, $x->abs/10), {legend => 'cubic',
                                             style => 'lw 5'}
             );
}

# plot a simple parabola and a cubic, joint args, with colors
{
  my $plot = PDL::Gnuplot->new(style    => 'points',
                               colormap => 1,
                               title    => 'polynomials',
                               xlabel   => 'x');

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat(PDL::cat($x**2, $x->abs/10),
                        PDL::cat($x**3, $x->abs/10)),
               {legend => 'parabola', style => 'lw 5'},
               {legend => 'cubic',    style => 'lw 5'}
             );
}


# plot a simple parabola and a cubic, separate args, with colors
{
  my $plot = PDL::Gnuplot->new(style    => 'circles',
                               colormap => 1,
                               title    => 'polynomials',
                               xlabel   => 'x',
                               zmin     => 0,
                               zmax     => 10
                              );

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat($x**2, $x->abs/10, $x->abs),
               {legend => 'parabola', style => 'lw 5'},
               PDL::cat($x**3, $x->abs/10, $x->abs),
               {legend => 'cubic',    style => 'lw 5'}
             );
}

# plot a simple parabola and a cubic, joint args, with colors AND circles
{
  my $plot = PDL::Gnuplot->new(style    => 'circles',
                               colormap => 1,
                               title    => 'polynomials',
                               xlabel   => 'x',
                               zmin     => 0,
                               zmax     => 10
                              );

  my $x = sequence(21) - 10;
  $plot->plot( $x,
               PDL::cat(PDL::cat($x**2, $x->abs/10, $x->abs),
                        PDL::cat($x**3, $x->abs/10, $x->abs)),
               {legend => 'parabola', style => 'lw 5'},
               {legend => 'cubic',    style => 'lw 5'}
             );
}

# plot a sphere
{
  my $plot = PDL::Gnuplot->new(style  => 'points',
                               title  => 'sphere',
                               '3d'   => 1,
                               square => 1);

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy, $z,
               {legend => 'sphere'}
             );
}

# plot a sphere, ellipse with 2 args
{
  my $plot = PDL::Gnuplot->new(style  => 'points',
                               title  => 'sphere',
                               '3d'   => 1,
                               square => 1);

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy,
               $z,   {legend => 'sphere'},
               $z*2, {legend => 'ellipse', style => 'with lines'}
             );
}

# plot a sphere, ellipse with a single arg
{
  my $plot = PDL::Gnuplot->new(style  => 'points',
                               title  => 'sphere single arg',
                               '3d'   => 1,
                               square => 1);

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy,
               $z->cat($z*2),
               {legend => 'sphere'},
               {legend => 'ellipse'}
             );
}

# sphere, ellipse: single range, double domain
{
  my $plot = PDL::Gnuplot->new(style  => 'points',
                               title  => 'sphere, ellipse made with 2 domains',
                               '3d'   => 1,
                               square => 1);

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy->cat($xy*2),
               $z,
               {legend => 'sphere'},
               {legend => 'ellipse'}
             );
}

# 2 spheres: 2 ranges, 2 domains
{
  my $plot = PDL::Gnuplot->new(style  => 'points',
                               title  => '2 spheres',
                               '3d'   => 1,
                               square => 1);

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy->cat($xy*2),
               $z ->cat($z*2),
               {legend => 'sphere'},
               {legend => 'ellipse'}
             );
}

# 2 spheres: 2 ranges, 2 domains, with colors
{
  my $plot = PDL::Gnuplot->new(style    => 'points',
                               title    => '2 spheres',
                               colormap => 1,
                               '3d'     => 1,
                               square   => 1);

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy->cat($xy*2),
               $z ->cat($z*2)->dummy(1,2),
               {legend => 'sphere'},
               {legend => 'ellipse'}
             );
}

# 2 spheres: 2 ranges, 2 domains, with colors, written to a pdf
{
  my $plot = PDL::Gnuplot->new(style    => 'points',
                               title    => '2 spheres',
                               colormap => 1,
                               '3d'     => 1,
                               square   => 1,
                               hardcopy => 'spheres.pdf');

  my $th = zeros(30)->           xlinvals( 0,          3.14159*2);
  my $ph = zeros(30)->transpose->ylinvals( -3.14159/2, 3.14159/2);


  my $xy = PDL::cat(PDL::flat( cos($ph)*cos($th) ),
                    PDL::flat( cos($ph)*sin($th) ));
  my $z = PDL::flat( sin($ph) * $th->ones );

  $plot->plot( $xy->cat($xy*2),
               $z ->cat($z*2)->dummy(1,2),
               {legend => 'sphere'},
               {legend => 'ellipse'}
             );
}
