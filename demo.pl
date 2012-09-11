#!/usr/bin/perl
use lib 'lib';

use PDL;
use PDL::NiceSlice;
use PDL::Graphics::Gnuplot qw(plot plot3d gpwin);

@windows = ();

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
plot(-$x, $x**3,{},
     $x,  $x**2);
plot(PDL::cat($x**2, $x**3));
plot(-$x,
     PDL::cat($x**2, $x**3));

# some more varied plotting, using the object-oriented interface
{
  my $plot = PDL::Graphics::Gnuplot->new("x11", 
                                         title => 'Error bars and other things',
					 {binary => 1, globalwith => 'linespoints', xmin => -10});

  $plot->plot( y2tics=>10,
	       with => 'lines lw 4',
	      legend => ['Parabola A','Parabola B','Parabola C'],
              axes => 'x1y2',
              PDL::cat($x, $x*2, $x*3), $x**2 - 300,

              with => 'xyerrorbars',
	      axes=>'x1y1',
              $x**2 * 10, $x**2/40, $x**2/2, # implicit domain

              {with => 'line', legend => 'cubic', tuplesize => 2},
              {legend => ['shifted cubic A','shifted cubic B']},
              $x, PDL::cat($x**3, $x**3 - 100) );
  push(@windows,$plot);
}

# a way to control the point size
$w=gpwin(x11,title=>"variable pointsize");
$w->plot(binary => 1, cbmin => -600, cbmax => 600, title=>"Variable pointsize",
     {with => 'points pointtype 7 pointsize variable'},
	 $x, $x/2, (10-abs($x))/2);
push(@windows,$w);

################################
# some 3d stuff
################################

# plot a sphere
$w=gpwin(x11,title=>"3d sphere");
$w->plot3d( binary => 1,
	    {with=>'points'},
	    $x_3d, $y_3d, $z_3d,
      );
push(@windows,$w);


print "Press RETURN to end demo...";
$a=<>;


__END__

# TO DO: fix syntax in the rest...

# sphere, ellipse together
$w=gpwin(x11,title=>"sphere and ellipse");
plot3d( binary => 1,
        j=>1,

        {legend => 'sphere'}, {legend => 'ellipse'},
        $x_3d->cat($x_3d*2),
        $y_3d->cat($y_3d*2), $z_3d );



# similar, written to a png
plot3d (binary => 1,
        globalwith => 'points', title    => 'sphere, ellipse',
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

  plot3d( binary => 1,
          globalwith => 'points', title  => 'gridded paraboloids',
          {legend => 'zplus'} , {legend=>'zminus'}, $z->cat(-$z),
          {legend => 'zplus2'}, $z*2);
}

# 3d, variable color, variable pointsize
{
 my $pi   = 3.14159;
 my $theta = zeros(200)->xlinvals(0, 6*$pi);
 my $z     = zeros(200)->xlinvals(0, 5);

 plot3d( binary => 1,
         title => 'double helix',

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
  plot3d(binary => 1,
         title  => 'Paraboloid heat map',
         extracmds => 'set view 0,0',
         with => 'image', inner($xy, $xy));
}

################################
# testing some error detection
################################

say STDERR "\n\n\n";
say STDERR "==== Testing error detection ====";
say STDERR 'I should complain about an invalid "with":';
say STDERR "=================================";
eval( <<'EOM' );
plot(with => 'bogusstyle', $x);
EOM
print STDERR $@ if $@;
say STDERR "=================================\n\n";


say STDERR 'PDL::Graphics::Gnuplot can detect I/O hanges. Here I ask for a delay, so I should detect this and quit after a few seconds:';
say STDERR "=================================";
eval( <<'EOM' );
  my $xy = zeros(21,21)->ndcoords - pdl(10,10);
  plot( extracmds => 'pause 10',
        sequence(5));
EOM
print STDERR $@ if $@;
say STDERR "=================================\n\n";
