##############################
#
# PDL::Graphics::Gnuplot
#
# This glue module is complicated because it connects a complicated
# syntax (Perl) to another complicated syntax (Gnuplot).  Here is a
# quick internal overview to get your bearings, above the usual POD.
#
# PDL::Graphics::Gnuplot (P:G:G) objects generally are associated with
# an external gnuplot process, and data are passed to the process
# through a pipe.  It is possible to intercept the data going through
# the pipe, either by diverting (dumping) data to stdout instead of
# gnuplot, or by teeing the data to stdout as well as gnuplot.
# Further, you can turn on syntax checking to validate P:G:G itself.
# Syntax checking is performed in a second P:G:G process, since
# screwing up the synchronization between Gnuplot and the P:G:G state
# is hazardous in the event of syntax error.
#
# The perl P:G:G object attempts to store and manage essentially
# all of the state that is also held inside the gnuplot program. 
# This takes the form of:
#      - Terminal options - setup for a given terminal output
#      - Plot options     - setup per-plot
#      - Curve options    - setup per-curve within a plot
#
# Option parsing uses branch tables.  Plot and curve options are
# parsed using the $pOptionsTable and $cOptionsTable respectively -
# these are big global hashes that describe the gnuplot syntax.
# Terminal options are "worser" - the options that are accepted depend
# on the terminal device, so the table $termTab contains # a
# description of which terminal options are allowed for each of the
# supported gnuplot terminals.
#
# All options handling is performed through parsing and emitter
# routines that are pointed to from those three tables.  That is
# handled with _parseOptHash(), which accepts an input parameter and a
# particular option description table, and parses the input according
# to the table.  The opposite (used for command generation) s
# _emitOpts(), which takes a parsed hash and emits an appropriate
# (sub)command into its returned string.
#
# There are some plot modes that we want to support, and that gnuplot
# itself does not yet support.  These are "mocked up" using data
# prefrobnicators.  Currently there is only one of those - FITS
# imagery.
#
# The gnuplot syntax is more than a little byzantine, and this is
# reflected in the code - specifically, in the code in plot(), which
# is the main workhorse.
#
# plot() pulls plot arguments off the front and back of the argument
# list, and relies on its sub-routine parseArgs to break the remaining
# parameters into chunks of parameters, each of which represents a
# single curve (including curve options and actual data to be
# plotted).  Because we allow threading, a given batch of curve option
# arguments and data can yield many chunks.  Those chunks are then
# passed through a number of steps back in the main plot() routine,
# and turned into a colllection of gnuplot commands suitable for plot
# generation.
# 
# Because option parsing is slightly more complicated than simply
# interpreting values and assigning defaults, we do not use a
# pre-existing package (such as PDL::Options) for option parsing - we
# use a dual parse table scheme.  Each option set has an "abbrev"
# table that is generated at compile time and resolves unique
# abbreviations; and a "parse" table that indicates what to do with 
# each option.  Since this mechanism is near at hand, we use it 
# even for routines (such as read_polygon) that could and would use
# PDL::Options in other circumstances.
#
=head1 NAME

PDL::Graphics::Gnuplot - Gnuplot-based plotting for PDL

=head1 SYNOPSIS

 pdl> use PDL::Graphics::Gnuplot;

 pdl> $x = sequence(101) - 50;
 pdl> gplot($x**2);
 pdl> gplot($x**2,{xr=>[0,50]});

 pdl> gplot( {title => 'Parabola with error bars'},
       with => 'xyerrorbars', legend => 'Parabola',
       $x**2 * 10, abs($x)/10, abs($x)*5 );

 pdl> $xy = zeros(21,21)->ndcoords - pdl(10,10);
 pdl> $z = inner($xy, $xy);
 pdl> gplot({title  => 'Heat map', '3d' => 1,
        extracmds => 'set view 0,0'},
        with => 'image', xvals($z),yvals($z),zeroes($z),$z*2);

 pdl> $w = gpwin();
 pdl> $pi    = 3.14159;
 pdl> $theta = zeros(200)->xlinvals(0, 6*$pi);
 pdl> $z     = zeros(200)->xlinvals(0, 5);
 pdl> $w->plot3d(cos($theta), sin($theta), $z);


=head1 DESCRIPTION

This module allows PDL data to be plotted using Gnuplot as a backend
for 2D and 3D plotting and image display.  Gnuplot (not affiliated
with the Gnu project) is a venerable, open-source plotting package
that produces both interactive and publication-quality plots on a very
wide variety of output devices.  Gnuplot is a standalone package that
must be obtained separately from this interface module.  It is
available through most Linux repositories, on MacOS via fink and
MacPorts, and from its website L<http://www.gnuplot.info>.

It is not necessary to understand the gnuplot syntax to generate
basic, or even complex, plots - though the full syntax is available
for advanced users who want to take advantage of the full flexibility
of the Gnuplot backend.

Gnuplot recognizes both hard-copy and interactive plotting devices,
and on interactive devices (like X11) it is possible to pan, scale,
and rotate both 2-D and 3-D plots interactively.  You can also enter
graphical data through mouse clicks on the device window.  On some
hardcopy devices (e.g. "PDF") that support multipage output, it is
necessary to close the device after plotting to ensure a valid file is
written out.

The main subroutine that C<PDL::Graphics::Gnuplot> exports by default
is C<gplot()>, which produces one or more overlain plots and/or images
in a single plotting window.  Depending on options, C<gplot()> can 
produce line plots, scatterplots, error boxes, "candlesticks", images,
or any overlain combination of these elements; or perspective views
of 3-D renderings such as surface plots.  

A call to C<gplot()> looks like:

 gplot({temp_plot_options}, # optional hash or array ref
      curve_options, data, data, ... ,
      curve_options, data, data, ... );

The data entries are columns to be plotted.  They are normally
an optional ordinate and a required abscissa, but some plot modes 
can use more columns than that.  The collection of columns is called
a "tuple".  Each column must be a separate PDL or an ARRAY ref.  If
all the columns are PDLs, you can add extra dimensions to make threaded
collections of curves.

PDL::Graphics::Gnuplot also implements an object oriented
interface. Plot objects track individual gnuplot subprocesses.  Direct
calls to C<gplot()> are tracked through a global object that stores
globally set configuration variables.

The C<gplot()> sub (or the C<plot()> method) collects two kinds of
options hash: B<plot options>, which describe the overall structure of
the plot being produced (e.g. axis specifications, window size, and
title), and B<curve options>, which describe the behavior of
individual traces or collections of points being plotted.  In
addition, the module itself supports options that allow direct
pass-through of plotting commands to the underlying gnuplot process.

=head2 Basic plotting

Gnuplot generates many kinds of plot, from basic line plots and histograms
to scaled labels.  Individual plots can be 2-D or 3-D, and different sets 
of plot styles are supported in each mode.  Plots can be sent to a variety
of devices; see the description of plot options, below.

You select a plot style with the "with" curve option, and feed in columns
of data (usually ordinate followed by abscissa).  The collection of columns
is called a "tuple".  These plots have two columns in their tuples:


 $x = xvals(51)-25; $y = $x**2;
 gplot(with=>'points', $x, $y);  # Draw points on a parabola
 gplot(with=>'lines', $x, $y);   # Draw a parabola
 gplot({title=>"Parabolic fit"},
       with=>"yerrorbars", legend=>"data", $x, $y+(random($y)-0.5)*2*$y/20, pdl($y/20),
       with=>"lines",      legend=>"fit",  $x, $y);

Normal threading rules apply across the arguments to a given plot.

All data are required to be supplied as either PDLs or list refs.
If you use a list ref as a data column, then normal
threading is disabled.  For example:

 $x = xvals(5);
 $y = xvals(5)**2;
 $labels = ['one','two','three','four','five'];
 gplot(with=>'labels',$x,$y,$labels);

See below for supported curve styles.

=head3 Modifying plots

Gnuplot is built around a monolithic plot model - it is not possible to 
add new data directly to a plot without redrawing the entire plot. To support
replotting, PDL::Graphics::Gnuplot stores the data you plot in the plot object,
so that you can add new data with the "replot" command:

 $w=gpwin(x11);
 $x=xvals(101)/100;
 $y=$x;
 $w->plot($x,$y);
 $w->replot($x,$y*$y);

For speed, the data are *not* disconnected from their original variables - so 
this will plot X vs. sqrt(X):

 $x = xvals(101)/100;
 $y = xvals(101)/100;
 $w->plot($x,$y);
 $y->inplace->sqrt;
 $w->replot($x,$y);

=head3 Image plotting

Several of the plot styles accept image data.  The tuple parameters work the
same way as for basic plots, but each "column" is a 2-D PDL rather than a 1-D PDL.
As a special case, the "with image" plot style accepts either a 2-D or a 3-D PDL.
If you pass in 3-D PDL, the extra dimension can have size 1, 3, or 4.  It is interpreted
as running across (R,G,B,A) color planes.  

=head3 3-D plotting

You can plot in 3-D by setting the plot option C<trid> to a true value.  Three
dimensional plots accept either 1-D or 2-D PDLs as data columns.  If you feed
in 2-D "columns", many of the common plot styles will generalize appropriately 
to 3-D.  For example, to plot a 2-D surface as a line grid, you can use the "lines"
style and feed in 2-D columns instead of 1-D columns.  

=head2 Plot styles supported

Gnuplot itself supports a wide range of plot styles, and all are supported by 
PDL::Graphics::Gnuplot.  Most of the basic plot styles collect tuples of 1-D columns
in 2-D mode (for ordinary plots), or either 1-D or 2-D "columns" in 3-D mode (for 
grid surface plots and such).  Image modes always collect tuples made of 2-D "columns".

You can pass in 1-D columns as either PDLs or ARRAY refs.  That is important for 
plot types (such as "labels") that require a collection of strings rather than 
numeric data.

The GNuplot plot styles supported are:

=over 3

=item * C<boxerrorbars> - combo of C<boxes> and C<yerrorbars>, below (2D)

=item * C<boxes> - simple boxes around regions on the plot (2D)

=item * C<boxxyerrorbars> - Render X and Y error bars as boxes (2D)

=item * C<candlesticks> - Y error bars with inner and outer limits (2D)

=item * C<circles> - circles with variable radius at each point: X/Y/radius (2D)

=item * C<dots> - tiny points ("dots") at each point, e.g. for scatterplots (2D/3D)

=item * C<ellipses> - ellipses.  Accepts X/Y/major/minor/angle (2D)

=item * C<filledcurves> - closed polygons or axis-to-line filled shapes (2D)

=item * C<financebars> - financial style plot. Accepts date/open/low/high/close (2D)

=item * C<fsteps> - square bin plot; delta-Y, then delta-X (see C<steps>, C<histeps>) (2D)

=item * C<histeps> - square bin plot; plateaus centered on X coords (see C<fsteps>, C<steps>) (2D)

=item * C<histogram> - binned histogram of dataset (not direct plot; see C<newhistogram>) (2D)

=item * C<fits> - (PDL-specific) renders FITS image files in scientific coordinates

=item * C<image> - Takes (i), (x,y,i), or (x,y,z,i).  See C<rgbimage>, C<rgbalpha>, C<fits>. (2D/3D)

=item * C<impulses> - vertical line from axis to the plotted point (2D/3D)

=item * C<labels> - Text labels at specified locations all over the plot (2D/3D)

=item * C<lines> - regular line plot (2D/3D)

=item * C<linespoints> - line plot with symbols at plotted points (2D/3D)

=item * C<newhistogram> - multiple-histogram-friendly histogram style (see C<histogram>) (2D)

=item * C<points> - symbols at plotted points (2D/3D)

=item * C<rgbalpha> - R/G/B color image with variable transparency (2D/3D)

=item * C<rgbimage> - R/G/B color image (2D/3D)

=item * C<steps> - square bin plot; delta-X, then delta-Y (see C<fsteps>, C<histeps>) (2D)

=item * C<vectors> - Small arrows: (x,y,[z]) -> (x+dx,y+dy,[z+dz]) (2D/3D)

=item * C<xerrorbars> - points with X error bars ("T" form) (2D)

=item * C<xyerrorbars> - points with both X and Y error bars ("T" form) (2D)

=item * C<yerrorbars> - points with Y error bars ("T" form) (2D)

=item * C<xerrorlines> - line plot with X errorbars at each point.  (2D)

=item * C<xyerrorlines> - line plot with XY errorbars at each point. (2D)

=item * C<yerrorlines> - line plot with Y error limits at each point. (2D)

=item * C<pm3d> - three-dimensional variable-position surface plot

=back

=head2 Options arguments

The plot options are parameters that affect the whole plot, like the title of
the plot, the axis labels, the extents, 2d/3d selection, etc. All the plot
options are described below in L</"Plot options">.  Plot options can be set directly
in the plot object, or passed to the plotting methods directly.  Plot options can
be passed in as a leading interpolated hash, as a leading hash ref, or as a trailing
hash ref in the argument list to any of the main plotting routines (C<gplot>, C<plot>,
C<image>, etc.).

The curve options are parameters that affect only one curve in particular. Each
call to C<plot()> can contain many curves, and options for a particular curve
I<precede> the data for that curve in the argument list. Furthermore, I<curve
options are all cumulative>. So if you set a particular style for a curve, this
style will persist for all the following curves, until this style is turned
off. The only exception to this is the C<legend> option, since it's very rarely
a good idea to have multiple curves with the same label. An example:

 gplot( with => 'points',  $x, $a,
        {y2   => 1},       $x, $b,
        with => 'lines',   $x, $c );

This plots 3 curves: $a vs. $x plotted with points on the main y-axis (this is
the default), $b vs. $x plotted with points on the secondary y axis, and $c
vs. $x plotted with lines also on the secondary y axis. Note that the curve
options can be supplied as either an inline hash or a hash ref.

All the curve options are described below in L</"Curve options">.

If you want to plot multiple curves of the same type without changing any options
between them, you must include an empty hash ref between the tuples for subsequent 
lines, as in:

 gplot( $x, $a, {}, $x, $b, {}, $x, $c );

=head2 Data arguments

Following the curve options in the C<plot()> argument list is the
actual data being plotted. Each output data point is a "tuple" whose
size varies depending on what is being plotted. For example if we're
making a simple 2D x-y plot, each tuple has 2 values; if we're making
a 3d plot with each point having variable size and color, each tuple
has 5 values (x,y,z,size,color). Each tuple element must be passed
separately.  For ordinary 2-D plots, the 0 dim of the tuple elements
runs across plotted point.  PDL threading is active, so you can plot
multiple curves with similar curve options on a normal 2-D plot, just
by stacking data inside the passed-in PDLs.  (An exception is that
threading is disabled if one or more of the data elements is a list
ref).

=head3 A simple example

   my $win = gpwin('x11');
   $win->plot( sin(xvals(45)) * 3.14159/10 );

Here we just plot a simple function.  The default plot style is a
line.  Line plots take a 2-tuple (X and Y values).  Since we have
supplied only one element, C<plot()> understands it to be the Y value
(abscissa) of the plot, and supplies value indices as X values -- so
we get a plot of just over 2 cycles of the sine wave over an X range
across X values from 0 to 44.

=head3 A not-so-simple example

   $win = gpwin('x11');
   $pi = 3.14159 
   $win->plot( {with => line}, xvals(10)**2, xvals(10),
               {with => circles}, 2 * xvals(50), 2 * sin(xvals(50) * $pi / 10), xvals(50)/20
    );

This plots sqrt(x) in an interesting way, and overplots some circles of varying size.  
The line plot accepts a 2-tuple, and we supply both X and Y.  The circles plot accepts
a 3-tuple: X, Y, and R.  

=head3 A complicated example:

   $pi    = 3.14159;
   $theta = xvals(201) * 6 * $pi / 200;
   $z     = xvals(201) * 5 / 200;

   gplot( {trid => 1, title => 'double helix'},
         {with => 'linespoints pointsize variable pointtype 2 palette',
         legend => ['spiral 1','spiral 2']} ,
         cdim=>1,
         pdl( cos($theta), -cos($theta) ),       # x
         pdl( sin($theta), -sin($theta) ),       # y
         $z,                                     # z
         (0.5 + abs(cos($theta))),               # pointsize
         sin($theta/3),                          # color
         {with=>'points pointsize variable pointtype 5'},
         zeroes(6),                         # x
         zeroes(6),                         # y
         xvals(6),                          # z
         xvals(6)+1                         # point size
   );

This is a 3d plot with variable size and color. There are 5 values in
the tuple.  The first 2 piddles have dimensions (N,2); all the other
piddles have a single dimension. The "cdim=>1" specifies that each column
of data should be one-dimensional. Thus the PDL threading generates 2
distinct curves, with varying values for x,y and identical values for
everything else.  To label the curves differently, 2 different sets of
curve options are given.  Omitting the "cdim" curve option would yield 
a 201x2 grid with the "linespoints" plotstyle, rather than two separate 
curves.

In addition to the threaded pair of linespoints curves, there are six 
variable size points plotted as filled squares, as a secondary curve.

Plot options are passed in in two places:  as a leading hash ref, and as 
a trailing hash ref.  Any other hash elements or hash refs must be curve
options.

Curves are delimited by non-data arguments.  After the initial hash
ref, curve options for the first curve (the threaded pair of spirals)
are passed in as a second hash ref.  The curve's data arguments are
ended by the first non-data argument (the hash ref with the curve
options for the second curve).

=head3 Implicit domains

When making a simple 2D plot, if exactly 1 dimension is missing,
PDL::Graphics::Gnuplot will use C<sequence(N)> as the domain. This is
why code like C<plot(pdl(1,5,3,4,4) )> works. Only one PDL is given
here, but the plot type ("lines" by default) requires 2 elements per
tuple. We are thus exactly 1 piddle short; C<sequence(5)> is used as
the missing domain PDL.  This is thus equivalent to 
C<plot(sequence(5), pdl(1,5,3,4,4) )>.

If plotting in 3d or displaying an image, an implicit domain will be
used if we are exactly 2 piddles short. In this case,
PDL::Graphics::Gnuplot will use a 2D grid as a domain. Example:

 my $xy = zeros(21,21)->ndcoords - pdl(10,10);
 plot({'3d' => 1},
       with => 'points', inner($xy, $xy));
 plot( with => 'image',  sin(rvals(51,51)) );

Here the only given piddle has dimensions (21,21). This is a 3D plot, so we are
exactly 2 piddles short. Thus, PDL::Graphics::Gnuplot generates an implicit
domain, corresponding to a 21-by-21 grid.

C<PDL::Graphics::Gnuplot> will group arguments greedily, so you need
to add separators when overplotting two separate curves on an implicit
domain.  For example, C<plot($a,$b)> is intepreting as plotting C<$b>
vs. C<$a>.  If you actually want to plot an overlay of both C<$a> and
C<$b> against array index, you want C<plot($a,{},$b)> instead.  The 
C<{}> is an empty hash ref. It serves to separate the argument list into
two curves.

=head2 Images

PDL::Graphics::Gnuplot supports four styles of image plot, via the "with" curve option.

The "image" style accepts a single image plane and displays it using
the palette (pseudocolor map) that is specified in the plot options for that plot.
As a special case, if you supply as data a (WxHx3) PDL it is treated as an RGB
image and displayed with the "rgbimage" style (below).  For quick
image display there is also an "image" method:

 use PDL::Graphics::Gnuplot qw/image/;
 $im = sin(rvals(51,51)/2);
 image( $im );                # display the image
 gplot( with=>'image', $im );  # display the image (longer form)

The colors are autoscaled in both cases.  To set a particular color range, use
the 'cbrange' plot option:

 image( {cbrange=>[0,1]}, $im );

You can plot rgb images directly with the image style, just by including a 
3rd dimension of size 3 on your image:

 $rgbim = pdl( xvals($im), yvals($im),rvals($im)/sqrt(2));
 image( $rgbim );                # display an RGB image
 gplot( with=>'image', $rgbim ); # display an RGB image (longer form)

Some additional plot styles exist to specify RGB and RGB transparent forms
directly.  These are the "with" styles "rgbimage" and "rgbalpha".  For each
of them you must specify the channels as separate PDLs:

 gplot( with=>'rgbimage', $rgbim->dog );           # RGB  the long way
 gplot( with=>'rgbalpha', $rgbim->dog, ($im>0) );  # RGBA the long way 

According to the gnuplot specification you can also give X and Y
values for each pixel, as in

 plot( with=>'image', xvals($im), yvals($im), $im )

but this appears not to work properly for anything more complicated
than a trivial matrix of X and Y values.

PDL::Graphics::Gnuplot provides a "fits" plot style that interprets
World Coordinate System (WCS) information supplied in the header of
the scientific image format FITS. The image is displayed in rectified
scientific coordinates, rather than in pixel coordinates.  You can plot
FITS images in scientific coordinates with

 gplot( with=>'fits', $fitsdata );

The fits plot style accepts a modifier "resample" (which may be
abbreviated), that allows you to downsample and/or rectify the image
before it is passed to the Gnuplot back-end.  This is useful either to
cut down on the burden of transferring large blocks of image data or
to rectify images with nonlinear WCS transformations in their headers.
(gnuplot itself has a bug that prevents direct rendering of images in
nonlinear coordinates).

 gplot( with=>'fits res 200', $fitsdata );
 gplot( with=>'fits res 100,400',$fitsdata );

to specify that the output are to be resampled onto a square 200x200
grid or a 100x400 grid, respectively.  The resample sizes must be
positive integers.

=head2 Interactivity

Several of the graphical backends of Gnuplot are interactive, allowing
the user to pan, zoom, rotate and measure the data in the plot
window. See the Gnuplot documentation for details about how to do
this. Some terminals (such as wxt) are persistently interactive. Other
terminals (such as x11) maintain their interactivity only while the
underlying gnuplot process is active -- i.e. until another plot is
created with the same PDL::Graphics::Gnuplot object, or until the perl
process exits (whichever comes first).  Still others (the hardcopy 
devices) aren't interactive at all.

Interactive devices also support mouse input: you can write PDL scripts
that accept and manipulate graphical input from the plotted window.

=head1 PLOT OPTIONS

Gnuplot controls plot style with "plot options" that configure and
specify virtually all aspects of the plot to be produced.   Plot
options are tracked as stored state in the PDL::Graphics::Gnuplot
object.  You can set them by passing them in to the constructor, to an
C<options> method, or to the C<plot> method itself.

Nearly all the underlying Gnuplot plot options are supported, as well
as some additional options that are parsed by the module itself for
convenience.

=head2 POs for Output: terminal, termoption, output, device, hardcopy

You can send plots to a variety of different devices; Gnuplot calls 
devices "terminals".  With the object-oriented interface, you must set
the output device with the constructor C<PDL::Graphics::Gnuplot::new> 
(or the exported constructor C<gpwin>) or the C<output> method.  If you
use the simple non-object interface, you can set the output with the 
C<terminal>, C<termoption>, and C<output> plot options.

C<terminal> sets the output device type for Gnuplot, and C<output> sets the 
actual output file or window number.  

C<device> and C<hardcopy> are for convenience.  C<device> offers a 
PGPLOT-style device specifier in "filename/device" format (the "filename"
gets sent to the "output" option, the "device" gets sent to the "terminal"
option). C<hardcopy> takes an output file name and attempts to parse out a 
file suffix and infer a device type.

For finer grained control of the plotting environment, you can send 
"terminal options" to Gnuplot.  If you set the terminal directly with 
plot options, you can include terminal options by interpolating them 
into a string, as in C<terminal jpeg interlace butt crop>, or you can
use the constructor C<new> (also exported as C<gpwin>), which parses
terminal options as an argument list. 

The routine C<PDL::Graphics::Gnuplot::terminfo> prints a list of all
availale terminals or, if you pass in a terminal name, options accepted
by that terminal.


=head2 POs for Titles: title, (x|x2|y|y2|z|cb)label, key

Gnuplot supports "enhanced" text escapes on most terminals; see "text",
below.

The C<title> option lets you set a title for the whole plot.

Individual plot components are labeled with the C<label> options.
C<xlabel>, C<x2label>, C<ylabel>, and C<y2label> specify axis titles
for 2-D plots.  The C<zlabel> works for 3-D plots.  The C<cblabel> option
sets the label for the color box, in plot types that have one (e.g.
image display).

(Don't be confused by C<clabel>, which doesnt' set a label at all, rather 
specifies the printf format used by contour labels in contour plots.)

C<key> controls where the plot key (that relates line/symbol style to label)
is placed on the plot.  It takes a scalar boolean indicating whether to turn the
key on (with default values) or off, or a list ref containing any of the following
arguments (all are optional) in the order listed:

=over 3

=item * ( on | off ) - turn the key on or off

=item * ( inside | outside | lmargin | rmargin | tmargin | bmargin | at <pos> )

These keywords set the location of the key -- "inside/outside" is
relative to the plot border; the margin keywords indicate location in
the margins of the plot; and at <pos> (where <pos> is a 2-list
containing (x,y): C<key=>[at=>[0.5,0.5]]>) is an exact location to place the key.

=item * ( left | right | center ) ( top | bottom | center ) - horiz./vert. alignment

=item * ( vertical | horizontal ) - stacking direction within the key

=item * ( Left | Right ) - justification of plot labels within the key (note case)

=item * [no]reverse - switch order of label and sample line

=item * [no]invert - invert the stack order of the labels

=item * samplen <length> - set the length of the sample lines

=item * spacing <dist> - set the spacing between adjacent labels in the list

=item * [no]autotitle - control whether labels are generated when not specified

=item * title "<text>" - set a title for the key

=item * [no]enhanced - override terminal settings for enhanced text interpretation

=item * font "<face>,<size>" - set font for the labels

=item * textcolor <colorspec> 

=item * [no]box linestyle <ls> linetype <lt> linewidth <lw> - control box around the key

=back

=head2 POs for axes, grids, & borders: grid, (x|x2|y|y2|z)zeroaxis, border

Normally, tick marks and their labels are applied to the border of a plot,
and no extra axes (e.g. the y=0 line) nor coordinate grids are shown.  You can
specify which (if any) zero axes should be drawn, and which (if any)
borders should be drawn.

The C<border> option controls whether the plot itself has a border
drawn around it.  You can feed it a scalar boolean value to indicate
whether borders should be drawn around the plot -- or you can feed in a list
ref containing options.  The options are all optional but must be supplied
in the order given.

=over 3

=item * <integer> - packed bit flags for which border lines to draw


The default if you set a true value for C<border> is to draw all border lines. 
You can feed in a single integer value containing a bit mask, to draw only some
border lines.  From LSB to MSB, the coded lines are bottom, left, top, right for 
2D plots -- e.g. 5 will draw bottom and top borders but neither left nor right.

In three dimensions, 12 bits are used to describe the twelve edges of
a cube surrounding the plot.  In groups of three, the first four
control the bottom (xy) plane edges in the same order as in the 2-D
plots; the middle four control the vertical edges that rise from the
clockwise end of the bottom plane edges; and the last four control the
top plane edges.

=item * ( back | front ) - draw borders first or last (controls hidden line appearance)

=item * linewidth <lw>, linestyle <ls>, linetype <lt> 

These are Gnuplot's usual three options for line control.

=back

The C<grid> option indicates whether gridlines should be drawn on
each axis.  It takes a list ref of arguments, each of which is either "no" or "m" or "",
followed by an axis name and "tics" --
e.g. C<< grid=>["noxtics","ymtics"] >> draws no X gridlines and draws
(horizontal) Y gridlines on Y axis major and minor tics, while
C<< grid=>["xtics","ytics"] >> or C<< grid=>["xtics ytics"] >> will draw both
vertical (X) and horizontal (Y) grid lines on major tics.

To draw a coordinate grid with default values, set C<< grid=>1 >>.  For more 
control, feed in a list ref with zero or more of the following parameters, in order:


The C<zeroaxis> keyword indicates whether to actually draw each axis
line at the corresponding zero along its indicated dimension.  For
example, to draw the X axis (y=0), use C<< xzeroaxis=>1 >>.  If you just
want the axis turned on with default values, you can feed in a Boolean
scalar; if you want to set its parameters, you can feed in a list ref
containing linewidth, linestyle, and linetype (with appropriate
parameters for each), e.g.  C<< xzeroaxis=>[linewidth=>2] >>.

=head2 POs for axis range and mode: (x|x2|y|y2|z|r|cb|t|u|v)range, autoscale, logscale

Gnuplot accepts explicit ranges as plot options for all axes.  Each option
accepts a list ref with (min, max).  If either min or max is missing, then
the opposite limit is autoscaled.  The x and y ranges refer to the usual 
ordinate and abscissa of the plot; x2 and y2 refer to alternate ordinate and 
abscissa; z if for 3-D plots; r is for polar plots; t, u, and v are for parametric
plots.  cb is for the color box on plots that include it (see "color", below).

C<rrange> is used for radial coordinates (which
are accessible using the C<mapping> plot option, below).

C<cbrange> (for 'color box range') sets the range of values over which
palette colors (either gray or pseudocolor) are matched.  It is valid
in any color-mapped plot (including images or palette-mapped lines or
points), even if no color box is being displayed for this plot.

C<trange>, C<urange>, and C<vrange> set ranges for the parametric coordinates
if you are plotting a parametric curve.

By default all axes are autoscaled unless you specify a range on that
axis, and partially (min or max) autoscaled if you specify a partial
range on that axis.  C<autoscale> allows more explicit control of how
autoscaling is performed, on an axis-by-axis basis.  It accepts a list
ref, each element of which specifies how a single axis should be
autoscaled.  Each element contains an axis name followed by one of
"fix,"min","max","fixmin", or "fixmax", e.g. 

 autoscale=>['xmax','yfix']

To not autoscale an axis at all, specify a range for it. The fix style of 
autoscaling forces the autoscaler to use the actual min/max of the data as
the limit for the corresponding axis -- by default the axis gets extended
to the next minor tic (as set by the autoticker or by a tic specification, see
below).

C<logscale> allows you to turn on logarithmic scaling for any or all
axes, and to set the base of the logarithm.  It takes a list ref, the
first element of which is a string mushing together the names of all
the axes to scale logarithmically, and the second of which is the base
of the logarithm: C<< logscale=>[xy=>10] >>.  You can also leave off the
base if you want base-10 logs: C<< logscale=>['xy'] >>.

=head2 POs for Axis tick marks - [m](x|x2|y|y2|z|cb)tics

Axis tick marks are called "tics" within Gnuplot, and they are extensively
controllable via the "<axis>tics" options.  In particular, major and minor
ticks are supported, as are arbitrarily variable length ticks, non-equally
spaced ticks, and arbitrarily labelled ticks.  Support exists for time formatted
ticks (see C<POs for time data values> below).

By default, gnuplot will automatically place major and minor ticks.
You can turn off ticks on an axis by setting the appropriate <foo>tics
option to a defined, false scalar value (e.g. C<< xtics=>0 >>), and turn them
on with default values by setting the option to a true scalar value
(e.g. C<< xtics=>1 >>). 

If you prepend an 'm' to any tics option, it affects minor tics instead of
major tics (major tics typically show units; minor tics typically show fractions
of a unit).

Each tics option can accept a list or hash ref containing options to
pass to Gnuplot.  If you want PDL::Graphics::Gnuplot to parse your options
for you (inserting commas and quotes, for example, where the gnuplot backend 
wants them), then you must pass in a hash ref.  

If you are comfortable with the Gnuplot backend's syntax, then you can 
pass in a scalar string or a list ref that is interpolated into a single
space-separated string to be passed to the gnuplot backend.  

The keywords accepted by the hash are:

=over 2

=item * axis - set this to 1 to place tics on the axis (the default)

=item * border - set this to 1 to place tics on the border (not the default)

=item * mirror - set this to 1 to place mirrored tics on the opposite axis/border?

=item * in - set this to 1 to draw tics inward from the axis/border

=item * out - set this to 1 to draw tics outward from the axis/border

=item * scale - multiplier on tic length.  

If you pass in undef, tics get the default length.  If you pass in a scalar, major tics get scaled.  You can pass in a list ref to scale minor tics too.

=item * rotate - turn label text by the given angle (in degrees)

=item * offset - offset label text from default position, (units: characters; requires list ref containing x,y)

=item * locations - sets tic locations.  list ref: [incr], [start, incr], or [start, incr, stop].

=item * labels - sets tic locations explicitly, with text labels for each. 

The labels should be a nested list ref that is a collection of duals
or triplets.  Each dual or triplet should contain
[label, position, minorflag], as in
C<labels=>[["one",1,0],["three-halves",1.5,1],["two",2,0]]>.

=item * format - printf-style formatting for tic labels

=item * font - set font name and size (system font name)

=item * rangelimited - set to 1 to limit tics to the range of values actually present in the plot

=item * textcolor - set the color of the ticks (see "color specs" below)

=back

For example, to turn on inward mirrored X axis ticks with diagonal Arial 9 text, use:

 xtics => {axis=>1,mirror=>1,in=>1,rotate=>45,font=>'Arial,9'}

or

 xtics => ['axis','mirror','in','rotate by 45','font "Arial,9"']

=head2 POs for time data values - (x|x2|y|y2|z|cb)(m|d)tics, (x|x2|y|y2|z|cb)data

Gnuplot contains support for plotting absolute time and date on any of its axes,
with conventional formatting. There are three main methods, which are mutually exclusive
(i.e. you should not attempt to use two at once on the same axis).

=over 3

=item B<Plotting timestamps using UNIX times>

You can set any axis to plot timestamps rather than numeric values by
setting the corresponding "data" plot option to "time",
e.g. C<xdata=>"time">.  If you do so, then numeric values in the
corresponding data are interpreted as UNIX time (seconds since the
UNIX epoch, neglecting leap seconds).  No provision is made for
UTC<->TAI conversion.  You can format how the times are plotted with
the "format" option in the various "tics" options(above).  Output
specifiers should be in UNIX strftime(3) format -- for example,
C<xdata=>"time",xtics=>{format=>"%Y-%b-%dT%H:%M:%S"}>
will plot UNIX times as ISO timestamps in the ordinate.

Due to limitations within gnuplot, the time resolution in this mode is 
limited to 1 second - if you want fractional seconds, you must use numerically
formatted times (and/or create your own tick labels using the C<labels> suboption 
to the C<?tics> option.

B<Timestamp format specifiers>

Time format specifiers use the following printf-like codes:

=over 3

=item Year A.D.: C<%Y> is 4-digit year; C<%y> is 2-digit year (1969-2068)

=item Month of year: C<%m>: 01-12; C<%b> or C<%h>: abrev. name; C<%B>: full name

=item Week of year: C<%W> (week starting Monday); C<%U> (week starting Sunday)

=item Day of year: C<%j> (1-366; boundary is midnight)

=item Day of month: C<%d> (01-31)

=item Day of week: C<%w> (0-6, Sunday=0), %a (abrev. name), %A (full name)

=item Hour of day: C<%k> (0-23); C<%H> (00-23); C<%l> (1-12); C<%I> (01-12)

=item Am/pm: C<%p> ("am" or "pm")

=item Minute of hour: C<%M> (00-60)

=item Second of minute: C<%S> (0-60)

=item Total seconds since start of 2000 A.D.: C<%s>

=item Timestamps: C<%T> (same as C<%H:%M:%S>); C<%R> (same as C<%H:%M>); C<%r> (same as C<%I:%M:%S %p>)

=item Datestamps: C<%D> (same as C<%m/%d/%y>); C<%F> (same as C<%Y-%m-%d>)

=item ISO timestamps: use C<%DT%T>.

=back

=item B<day-of-week plotting>

If you just want to plot named days of the week, you can instead use
the C<dtics> options set plotting to day of week, where 0 is Sunday and 6
is Saturday; values are interpreted modulo 7.  For example, C<<
xmtics=>1,xrange=>[-4,9] >> will plot two weeks from Wednesday to
Wednesday. As far as output format goes, this is exactly equivalent to 
using the C<%w> option with full formatting - but you can treat the 
numeric range in terms of weeks rather than seconds.

=item B<month-of-year plotting>

The C<mtics> options set plotting to months of the year, where 1 is January and 12 is 
December, so C<< xdtics=>1, xrange=>[0,4] >> will include Christmas through Easter.
This is exactly equivalent to using the C<%d> option with full formatting - but you 
can treat the numeric range in terms of months rather than seconds.

=back

=head2 POs for location/size - (t|b|l|r)margin, offsets, origin, size, justify, clip

Adjusting the size, location, and margins of the plot on the plotting
surface is something of a null operation for most single plots -- but
you can tweak the placement and size of the plot with these options.
That is particularly useful for multiplots, where you might like to
make an inset plot or to lay out a set of plots in a custom way.

The margin options accept scalar values -- either a positive number of
character heights or widths of margin around the plot compared to the
edge of the device window, or a string that starts with "at screen "
and interpolates a number containing the fraction of the plot window
offset.  The "at screen" technique allows exact plot placement and is
an alternative to the C<origin> and C<size> options below.

The C<offsets> option allows you to put an empty boundary around the
data, inside the plot borders, in an autosacaled graph.  The offsets
only affect the x1 and y1 axes, and only in 2D plot commands.
C<offsets> accepts a list ref with four values for the offsets, which
are given in scientific (plotted) axis units.

The C<origin> option lets you specify the origin (lower left corner)
of an individual plot on the plotting window.  The coordinates are 
screen coordinates -- i.e. fraction of the total plotting window.  

The size option lets you adjust the size and aspect ratio of the plot, 
as an absolute fraction of the plot window size.  You feed in fractional
ratios, as in C<< size=>[$xfrac, $yfrac] >>.  You can also feed in some keywords
to adjust the aspect ratio of the plot.  The size option overrides any 
autoscaling that is done by the auto-layout in multiplot mode, so use 
with caution -- particularly if you are multiplotting.  You can use
"size" to adjust the aspect ratio of a plot, but this is deprecated 
in favor of the pseudo-option C<justify>.

C<justify> sets the scientific aspect ratio of a 2-D plot.  Unity 
yields a plot with a square scientific aspect ratio.  Larger
numbers yield taller plots. 

C<clip> controls the border between the plotted data and the border of the plot.
There are three clip types supported:   points, one, and two.  You can set them 
independently by passing in booleans with their names: C<< clip=>[points=>1,two=>0] >>.

=head2 POs for Color: colorbox, palette, clut

Color plots are supported via RGB and pseudocolor.  Plots that use pseudcolor or
grayscale can have a "color box" that shows the photometric meaning of the color.

The colorbox generally appears when necessary but can be controlled manually
with the C<colorbox> option.  C<colorbox> accepts a scalar boolean value indicating
whether or no to draw a color box, or a list ref containing additional options.  
The options are all, well, optional but must appear in the order given:

=over 3

=item ( vertical | horizontal ) - indicates direction of the gradient in the box

=item ( default | user ) - indicates user origin and size

If you specify C<default> the colorbox will be placed on the right-hand side of the plot; if you specify C<user>, you give the location and size in subsequent arguments:

 colorbox => [ 'user', 'origin'=>"$x,$y", 'size' => "$x,$y" ]

=item ( front | back ) - draws the colorbox before or after the plot

=item ( noborder | bdefault | border <line style> ) - specify border

The line style is a numeric type as described in the gnuplot manual.

=back

The C<palette> option offers many arguments that are not fully
documented in this version but are explained in the gnuplot manual.
It offers complete control over the pseudocolor mapping function.

For simple color maps, C<clut> gives access to a set of named color
maps.  (from "Color Look Up Table").  A few existing color maps are:
"default", "gray", "sepia", "ocean", "rainbow", "heat1", "heat2", and
"wheel".  To see a complete list, specify an invalid table,
e.g. C<< clut=>'xxx' >>.  (This should be improved in a future version).

=head2 POs for 3D: trid, view, pm3d, hidden3d, dgrid3d, surface, xyplane, mapping

If C<trid> or its synonym C<3d> is true, Gnuplot renders a 3-D plot.
This changes the default tuple size from 2 to 3.  This
option is used to switch between the Gnuplot "plot" and "splot"
command, but it is tracked with persistent state just as any other
option.

The C<view> option controls the viewpoint of the 3-D plot.  It takes a
list of numbers: C<< view=>[$rot_x, $rot_z, $scale, $scale_z] >>.  After
each number, you can omit the subsequent ones.  Alternatively,
C<< view=>['map'] >> represents the drawing as a map (e.g. for contour
plots) and C<< view=>[equal=>'xy'] >> forces equal length scales on the X
and Y axes regardless of perspective, while C<< view=>[equal=>'xyz'] >>
sets equal length scales on all three axes.

The C<pm3d> option accepts several parameters to control the pm3d plot style,
which is a palette-mapped 3d surface.  They are not documented here in this
version of the module but are explained in the gnuplot manual.  

C<hidden3d> accepts a list of parameters to control how hidden surfaces are
plotted (or not) in 3D. It accepts a boolean argument indicating whether to hide
"hidden" surfaces and lines; or a list ref containing parameters that control how 
hidden surfaces and lines are handled.  For details see the gnuplot manual.

C<xyplane> sets the location of that plane (which is drawn) relative
to the rest of the plot in 3-space.  It takes a single string: "at" or
"relative", and a number.  C<< xyplane=>[at=>$z] >> places the XY plane at the
stated Z value (in scientific units) on the plot.  C<< xyplane=>[relative=>$frac] >>
places the XY plane $frac times the length of the scaled Z axis *below* the Z 
axis (i.e. 0 places it at the bottom of the plotted Z axis; and -1 places it 
at the top of the plotted Z axis).

C<mapping> takes a single string: "cartesian", "spherical", or
"cylindrical".  It determines the interpretation of data coordinates
in 3-space. (Compare to the C<polar> option in 2-D).

=head2 POs for Contour plots - contour, cntrparam

Contour plots are only implemented in 3D.  To make a normal 2D contour
plot, use 3-D mode, but set the view to "map" - which projects the 3-D
plot onto its 2-D XY plane. (This is convoluted, for sure -- future
versions of this module may have a cleaner way to do it).

C<contour> enables contour drawing on surfaces in 3D.  It takes a
single string, which should be "base", "surface", or "both".

C<cntrparam> manages how contours are generated and smoothed.  It
accepts a list ref with a collection of Gnuplot parameters that are
issued one per line; refer to the Gnuplot manual for how to operate
it.

=head2 POs for Polar plots - polar, angles, mapping

You can make 2-D polar plots by setting C<polar> to a true value.  The 
ordinate is then plotted as angle, and the abscissa is radius on the plot.
The ordinate can be in either radians or degrees, depending on the 
C<angles> parameter

C<angles> takes either "degrees" or "radians" (default is radians).

C<mapping> is used to set 3-D polar plots, either cylindrical or spherical 
(see the section on 3-D plotting, above).

=head2 POs for Markup - label, arrow, object

You specify plot markup in advance of the plot command, with plot
options (or add it later with the C<replot> method).  The options give
you access to a collection of (separately) numbered descriptions that
are accumulated into the plot object.  To add a markup object to the
next plot, supply the appropriate options as a list ref or as a single
string.  To specify all markup objects at once, supply the appropriate
options for all of them as a nested list-of-lists.

To modify an object, you can specify it by number, either by appending
the number to the plot option name (e.g. C<arrow3>) or by supplying it
as the first element of the option list for that object.  

To remove all objects of a given type, supply undef (e.g. C<< arrow=>undef >>).

For example, to place two labels, use the plot option:

 label => [["Upper left",at=>"10,10"],["lower right",at=>"20,5"]];

To add a label to an existing plot object, if you don't care about what
index number it gets, do this:

 $w->options( label=>["my new label",at=>[10,20]] );

If you do care what index number it gets (or want to replace an existing label), 
do this:

 $w->options( label=>[$n, "my replacement label", at=>"10,20"] );

where C<$w> is a Gnuplot object and C<$n> contains the label number
you care about.


=head3 label - add a text label to the plot.

The C<label> option allows adding small bits of text at arbitrary
locations on the plot.

Each label specifier list ref accepts the following suboptions, in 
order.  All of them are optional -- if no options other than the index
tag are given, then any existing label with that index is deleted.

For examples, please refer to the Gnuplot 4.4 manual, p. 117.

=over 3

=item <tag> - optional index number (integer)

=item <label text> - text to place on the plot.

You may supply double-quotes inside the string, but it is not
necessary in most cases (only if the string contains just an integer
and you are not specifying a <tag>.

=item at <position> - where to place the text (sci. coordinates)

The <position> should be a string containing a gnuplot position specifier.
At its simplest, the position is just two numbers separated by
a comma, as in C<< label2=>["foo",at=>"5,3" >>, to specify (X,Y) location 
on the plot in scientific coordinates.  Each number can be preceded
by a coordinate system specifier; see the Gnuplot 4.4 manual (page 20) 
for details.

=item ( left | center | right ) - text placement rel. to position

=item rotate [ by <degrees> ] - text rotation

If "rotate" appears in the list alone, then the label is rotated 90 degrees
CCW (bottom-to-top instead of left-to-right).  The following "by" clause is
optional.

=item font "<name>,<size>" - font specifier

The <name>,<size> must be double quoted in the string (this may be fixed
in a future version), as in

 C<< label3=>["foo",at=>"3,4",font=>'"Helvetica,18"'] >>.

=item noenhanced - turn off gnuplot enhanced text processing (if enabled)

=item ( front | back ) - rendering order (last or first)

=item textcolor <colorspec> 

=item (point <pointstyle> | nopoint ) - control whether the exact position is marked

=item offset <offset> - offfset from position (in points).

=back

=head3 arrow - place an arrow or callout line on the plot

Works similarly to the C<label> option, but with an arrow instead of text.

The arguments, all of which are optional but which must be given in the order listed,
are:

=over 3

=item from <position> - start of arrow line

The <position> should be a string containing a gnuplot position specifier.
At its simplest, the position is just two numbers separated by
a comma, as in C<< label2=>["foo",at=>"5,3" >>, to specify (X,Y) location 
on the plot in scientific coordinates.  Each number can be preceded
by a coordinate system specifier; see the Gnuplot 4.4 manual (page 20) 
for details.

=item ( to | rto ) <position>  - end of arrow line

These work like C<from>.  For absolute placement, use "to".  For placement
relative to the C<from> position, use "rto". 

=item (arrowstyle | as) <arrow_style>

This specifies that the arrow be drawn in a particualr predeclared numerical
style.  If you give this parameter, you shoudl omit all the following ones.

=item ( nohead | head | backhead | heads ) - specify arrowhead placement

=item size <length>,<angle>,<backangle> - specify arrowhead geometry

=item ( filled | empty | nofilled ) - specify arrowhead fill

=item ( front | back ) - specify drawing order ( last | first )

=item linestyle <line_style> - specify a numeric linestyle

=item linetype <line_type> - specify numeric line type

=item linewidth <line_width> - multiplier on the width of the line

=back

=head3 object - place a shape on the graph

C<object>s are rectangles, ellipses, circles, or polygons that can be placed
arbitrarily on the plotting plane.

The arguments, all of which are optional but which must be given in the order listed, are:

=over 3

=item <object-type> <object-properties> - type name of the shape and its type-specific properties

The <object-type> is one of four words: "rectangle", "ellipse", "circle", or "polygon".  

You can specify a rectangle with C<< from=>$pos1, [r]to=>$pos2 >>, with C<< center=>$pos1, size=>"$w,$h" >>,
or with C<< at=>$pos1,size=>"$w,$h" >>.

You can specify an ellipse with C<< at=>$pos, size=>"$w,$h" >> or C<< center=>$pos size=>"$w,$h" >>, followed
by C<< angle=>$a >>.

You can specify a circle with C<< at=>$pos, size=>"$w,$h" >> or C<< center=>$pos size=>"$w,$h" >>, followed 
by C<> size=>$radius >> and (optionally) C<< arc=>"[$begin:$end]" >>.

You can specify a polygon with C<< from=>$pos1,to=>$pos2,to=>$pos3,...to=>$posn >> or with 
C<< from=>$pos1,rto=>$diff1,rto=>$diff2,...rto=>$diffn >>.

=item ( front | back | behind ) - draw the object last | first | really-first.

=item fc <colorspec> - specify fill color

=item fs <fillstyle> - specify fill style

=item lw <width> - multiplier on line width

=back

=head2 POs for appearance tweaks - bars, boxwidth, isosamples, pointsize, style

TBD - more to come.

=head2 POs for locale/internationalization - locale, decimalsign

C<locale> is used to control date stamp creation.  See the gnuplot manual.

C<decimalsign>  accepts a character to use in lieu of a "." for the decimalsign.
(e.g. in European countries use C<< decimalsign=>',' >>).

C<globalwith> is used as a default plot style if no valid 'with' curve option is present for
a given curve.

If set to a nonzero value, C<timestamp> causes a time stamp to be
placed on the side of the plot, e.g. for keeping track of drafts.

C<zero> sets the approximation threshold for zero values within gnuplot.  Its default is 1e-8.

C<fontpath> sets a font search path for gnuplot.  It accepts a collection of file names as a list ref.

=head2 Advanced Gnuplot tweaks: topcmds, extracmds, bottomcmds, binary, dump, log

Plotting is carried out by sending a collection of commands to an underlying
gnuplot process.  In general, the plot options cause "set" commands to be 
sent, configuring gnuplot to make the plot; these are followed by a "plot" or 
"splot" command and by any cleanup that is necessary to keep gnuplot in a known state.

Provisions exist for sending commands directly to Gnuplot as part of a plot.  You
can send commands at the top of the configuration but just under the initial
"set terminal" and "set output" commands (with the C<topcmds> option), at the bottom
of the configuration and just before the "plot" command (with the C<extracmds> option),
or after the plot command (with the C<bottomcmds> option).  Each of these plot
options takes a list ref, each element of which should be one command line for
gnuplot.

Most plotting is done with binary data transfer to Gnuplot; however, due to 
some bugs in Gnuplot binary handling, certain types of plot data are sent in ASCII.
In particular, time series and label data require transmission in ASCII (as of Gnuplot 4.4). 
You can force ASCII transmission of all but image data by explicitly setting the
C<< binary=>0 >> option.

C<dump> is used for debugging. If true, it writes out the gnuplot commands to STDOUT
I<instead> of writing to a gnuplot process. Useful to see what commands would be
sent to gnuplot. This is a dry run. Note that this dump will contain binary
data, if the 'binary' option is given (see below)

C<tee> is used for debugging. If true, writes out the gnuplot commands to STDERR I<in
addition> to writing to a gnuplot process. This is I<not> a dry run: data is
sent to gnuplot I<and> to the log. Useful for debugging I/O issues. Note that
this log will contain binary data, if the 'binary' option is given (see below)

=head1 CURVE OPTIONS 

The curve options describe details of specific curves within a plot. 
They are in a hash, whose keys are as follows:

=over 2

=item legend

Specifies the legend label for this curve

=item with

Specifies the style for this curve. The value is passed to gnuplot
using its 'with' keyword, so valid values are whatever gnuplot
supports.  See below for a list of supported curve styles.

=item axes

Lets you specify which X and/or Y axes to plot on.  Gnuplot supports
a main and alternate X and Y axis.  You specify them as a packed string
with the x and y axes indicated: for example, C<x1y1> to plot on the main
axes, or C<x1y2> to plot using an alternate Y axis (normally gridded on
the right side of the plot).

=item tuplesize

Specifies how many values represent each data point.  Normally you
don't need to set this as individual C<with> styles implicitly set a
tuple size (which is automatically extended if you specify additional
modifiers such as C<palette> that require more data); this option 
lets you override PDL::Graphics::Gnuplot's parsing in case of irregularity.

=item cdims 

Specifies the dimensions of of each column in this curve's tuple.  It must 
be 0, 1, or 2.   Normally you don't need to set this for most plots; the 
main use is to specify that a 2-D data PDL is to be interpreted as a collection
of 1-D columns rather than a single 2-D grid (which would be the default
in a 3-D plot). For example:

    $w=gpwin();
    $r2 = rvals(21,21)**2;
    $w->plot3d( wi=>'lines', xvals($r2), yvals($r2), $r2 );

will produce a grid of values on a paraboloid. To instead plot a collection
of lines using the threaded syntax, try

    $w->plot3d( wi=>'lines', cd=>1, xvals($r2), yvals($r2), $r2 );

which will plot 21 separate curves in a threaded manner.

=back

=head1 RECIPES

Most of these come directly from Gnuplot commands. See the Gnuplot docs for
details.

=head2 2D plotting

If we're plotting a piddle $y of y-values to be plotted sequentially (implicit
domain), all you need is

  plot($y);

If we also have a corresponding $x domain, we can plot $y vs. $x with

  plot($x, $y);

=head3 Simple style control

To change line thickness:

  plot(with => 'lines linewidth 4', $x, $y);

To change point size and point type:

  plot(with => 'points pointtype 4 pointsize 8', $x, $y);

=head3 Errorbars

To plot errorbars that show $y +- 1, plotted with an implicit domain

  plot(with => 'yerrorbars', $y, $y->ones);

Same with an explicit $x domain:

  plot(with => 'yerrorbars', $x, $y, $y->ones);

Symmetric errorbars on both x and y. $x +- 1, $y +- 2:

  plot(with => 'xyerrorbars', $x, $y, $x->ones, 2*$y->ones);

To plot asymmetric errorbars that show the range $y-1 to $y+2 (note that here
you must specify the actual errorbar-end positions, NOT just their deviations
from the center; this is how Gnuplot does it)

  plot(with => 'yerrorbars', $y, $y - $y->ones, $y + 2*$y->ones);

=head3 More multi-value styles

In Gnuplot 4.4.0, these generally only work in ASCII mode. This is a bug in
Gnuplot that will hopefully get resolved.

Plotting with variable-size circles (size given in plot units, requires Gnuplot >= 4.4)

  plot(with => 'circles', $x, $y, $radii);

Plotting with an variably-sized arbitrary point type (size given in multiples of
the "default" point size)

  plot(with => 'points pointtype 7 pointsize variable', 
       $x, $y, $sizes);

Color-coded points

  plot(with => 'points palette', 
       $x, $y, $colors);

Variable-size AND color-coded circles. A Gnuplot (4.4.0) bug make it necessary to
specify the color range here

  plot(cbmin => $mincolor, cbmax => $maxcolor,
       with => 'circles palette', 
       $x, $y, $radii, $colors);

=head2 3D plotting

General style control works identically for 3D plots as in 2D plots.

To plot a set of 3d points, with a square aspect ratio (squareness requires
Gnuplot >= 4.4):

  plot3d(square => 1, $x, $y, $z);

If $xy is a 2D piddle, we can plot it as a height map on an implicit domain

  plot3d($xy);

Complicated 3D plot with fancy styling:

  my $pi    = 3.14159;
  my $theta = zeros(200)->xlinvals(0, 6*$pi);
  my $z     = zeros(200)->xlinvals(0, 5);

  plot3d(title => 'double helix',

         { with => 'linespoints pointsize variable pointtype 7 palette',
           legend => 'spiral 1' },
         { legend => 'spiral 2' },

         # 2 sets of x, 2 sets of y, single z
         PDL::cat( cos($theta), -cos($theta)),
         PDL::cat( sin($theta), -sin($theta)),
         $z,

         # pointsize, color
         0.5 + abs(cos($theta)), sin(2*$theta) );

3D plots can be plotted as a heat map. As of Gnuplot 4.4.0, this doesn't work in binary.

  plot3d( extracmds => 'set view 0,0',
          with => 'image',
          $xy );

=head2 Hardcopies

To send any plot to a file, instead of to the screen, one can simply do

  plot(hardcopy => 'output.pdf',
       $x, $y);

The C<hardcopy> option is a shorthand for the C<terminal> and
C<output> options. The output device is chosen from the file name
suffix.  

If you want more (any) control over the output options (e.g. page
size, font, etc.) then you can specify the output device using the
C<ouput> method or the constructor itself -- or the corresponding plot
options in the non-object mode. For example, to generate a PDF of a
particular size with a particular font size for the text, one can do

  plot(terminal => 'pdfcairo solid color font ",10" size 11in,8.5in',
       output   => 'output.pdf',
       $x, $y);

This command is equivalent to the C<hardcopy> shorthand used previously, but the
fonts and sizes can be changed.

Using the object oriented mode, you could instead say:

  $w = gpwin();
  $w->plot( $x, $y );
  $w->output( pdfcairo, solid=>1, color=>1,font=>',10',size=>[11,8.5,'in'] );
  $w->replot();
  $w->close();

Many hardcopy output terminals (such as C<pdf> and C<svg>) will not 
dump their plot to the file unless the file is explicitly closed with a 
change of output device or a call to C<reset>, C<restart>, or C<close>.
This is because those devices support multipage output and also require 
and end-of-file marker to close the file.

=head1 Methods 

=cut

package PDL::Graphics::Gnuplot;

use strict;
use warnings;
use PDL;
use List::Util qw(first);
use Storable qw(dclone);
use IPC::Open3;
use IPC::Run;
use IO::Select;
use Symbol qw(gensym);
use Time::HiRes qw(gettimeofday tv_interval);
our $VERSION = '1.2';
our $gp_version = undef;   # eventually gets the extracted gnuplot(1) version number.

use base 'Exporter';
our @EXPORT_OK = qw(plot plot3d line lines points image terminfo reset restart replot);
our @EXPORT = qw(gpwin gplot greplot greset grestart);

our $check_syntax = 0;
our $gnuplot_req_v = 4.4;

our $MS_io_braindamage = ($^O =~ m/MSWin32/i);    # Do some different things on Losedows
our $debug_echo = 0;                              # If set, inject commands into the returned stream to mimic Losedows

# when testing plots with binary i/o, this is the unit of test data
my $testdataunit_binary = "........"; # 8 bytes - length of an IEEE double

# if I call plot() as a global function I create a new PDL::Graphics::Gnuplot
# object. I would like the gnuplot process to persist to keep the plot
# interactive at least while the perl program is running. This global variable
# keeps the new object referenced so that it does not get deleted. Once can
# create their own PDL::Graphics::Gnuplot objects, but there's one free global
# one available
my $globalPlot;

# get a list of all the -- options that this gnuplot supports
my %gnuplotFeatures = _getGnuplotFeatures();

# Separate parse tables are maintained for plot and curve options, as package globals. 
# These are they.  (Set below).
our($pOpt, $cOpt);

our $cmdFence = "cmdFENCEcmd";

##############################
#
# Constructor(s)
#
# gpwin & new - constructor
# DESTROY - destructor kills gnuplot task
#
# _startGnuplot - helper for new


=head2 gpwin - exported constructor (synonymous with new)

=for usage

 use PDL::Graphics::Gnuplot;

 $w = gpwin( @options );
 $w->plot( @plot_args );

=for ref 

This is just a synonym for the "new" method.  It is exported into the
current package by default for convenience.

=cut

sub gpwin { return new("PDL::Graphics::Gnuplot",@_); }

=head2 new - object constructor

=for usage

    $w = new PDL::Graphics::Gnuplot;
    $w->plot( @plot_args );

    # Specify plot options alone
    $w = new PDL::Graphics::Gnuplot( {%plot_options} );

    # Specify device and device options (and optional default plot options)
    $w = new PDL::Graphics::Gnuplot( device, %device_options, {%plot_options} );
    $w->plot( @plot_args );


=for ref

Creates a PDL::Graphics::Gnuplot persistent plot object, and connects it to gnuplot.

For convenience, you can specify the output device and its options
right here in the constructor.  Because different gnuplot devices
accept different options, you must specify a device is you want to
specify any device configuration options (such as window size, output
file, text mode, or default font).  

If you don't specify a device type, then the Gnuplot default device
for your system gets used.  You can set that with an environment
variable (check the Gnuplot documentation).

Gnuplot uses the term "terminal" for output devices; you can see a
list of terminals supported by PDL::Graphics::Gnuplot by invoking
C<PDL::Graphics::Gnuplot::terminfo()> (for example in the perldl shell).

For convenience, you can provide default plot options here.  If the last
argument to C<new()> is a trailing hash ref, it is treated as plot options.

After you have created an object, you can change its terminal/output
device with the C<output> method, which is useful for (e.g.) throwing
up an interactive plot and then sending it to a hardcopy device. See
C<output> for a description of terminal options and how to format
them.

=for example

  my $plot = PDL::Graphics::Gnuplot->new({title => 'Object-oriented plot'});
  $plot->plot( legend => 'curve', sequence(5) );


=cut

our $termTab;

sub new
{
  my $classname = shift;

  # Declare & bless minimal object to hold everything.
  my $this = { t0          => [gettimeofday],   # last access
	       options     => {multiplot=>0},   # multiplot option actually holds multiplotting state flag
	       replottable => 0,                # small amount of state...
	       interactive => 0,
              };
  bless($this,$classname);

  output($this, @_);

  # now that options are parsed, start up a gnuplot
  # and copy the keys into the object
  _startGnuplot($this,'main');
  _startGnuplot($this,'syntax') if($check_syntax);
  
  _logEvent($this, "startGnuplot() finished") if ($this->{options}{tee});

  return $this;
}

##############################
# output - set output terminal and options.

=head2 output - set the output device and options for a Gnuplot object

=for usage

    $window->output( device, %device_options, {plot_options} );

=for ref

You can control the output device of a PDL::Graphics::Gnuplot object on
the fly.  That is useful, for example, to replot several versions of the 
same plot to different output devices (interactive and hardcopy).

Gnuplot interprets plot options differently per device.
PDL::Graphics::Gnuplot attempts to interpret some of the more common
ones in a common way.  In particular:

=over 3

=item size

Most drivers support a "size" option to specify the size of the output
plotting surface.  The format is [$width, $height, $unit]; the
trailing unit string is optional but recommended, since the default
unit of length changes from device to device.

The unit string can be in, cm, mm, px, or pt.  Pixels are taken to 
be 1 point in size (72 pixels per inch) and dimensions are 
computed accordingly.  

=item output

This option actually sets the object's "output" option for most terminal
devices; that changes the file to which the plot will be written.  Some
devices, notably X11 and Aqua, don't make proper use of "output"; for those
devices, specifying "output" in the object constructor actually sets the
appropriate terminal option (e.g. "window" in the X11 terminal).
This is described as a "plot option" in the Gnuplot manual, but it is
treated as a setup variable and parsed with the setup/terminal options here
in the constructor.

=item enhanced

This is a flag that indicates whether to enable Gnuplot's enhanced text
processing (e.g. for superscripts and subscripts).  Set it to a false
value for plain text, to a true value for enhanced text.  See the Gnuplot
manual for a description of the syntax.

=back

For a brief description of the plot options that any one device supports, 
you can run PDL::Graphics::Gnuplot::terminfo().

As with plot options, terminal options can be abbreviated to the shortest
unique string -- so (e.g.) "size" can generally be abbreviated "si" and 
"monochrome" can be abbreviated "mono" or "mo".

=cut

sub output {
    my $this = _obj_or_global(\@_);

    # Check if the last passed-in parameter is a hash ref -- if it is, then it is plot options
    my $poh;
    if( (0+@_) && ref($_[$#_]) eq 'HASH') {
	$poh = pop @_;
    }
    # parse plot options (if any)
    if($poh) {
	options($this,$poh);
    }
    
    if(@_) {
	# Check that, if there is at least one more argument, it is recognizable as a terminal
	my $terminal;
	$terminal = lc(shift);
	if(!exists($termTab->{$terminal})) {
	    my $s = "PDL::Graphics::Gnuplot::new: the first argument to new must be a terminal type.\n".
		terminfo('',1);
	    barf($s);
	}
	
	# Generate abbrevs on first invokation for each terminal type.
	unless($termTab->{$terminal}->{opt}->[1]) {
	    $termTab->{$terminal}->{opt}->[1] = _gen_abbrev_list(keys %{$termTab->{$terminal}->{opt}[0]});
	    $termTab->{$terminal}->{opt}->[0]->{__unit__} = ['s','-']; # Hack so we can stash the unit string in there later.
	}
	
	
	my $termOptions = {};
	
	# parse "terminal" options
	if($termTab->{$terminal} && $termTab->{$terminal}->{opt}) {
	    
	    # Stuff the default size unit into the options hash, so that the parser has access to it.
	    $termOptions->{'__unit__'} = $termTab->{$terminal}->{unit};
	    
	    _parseOptHash( $termOptions, $termTab->{$terminal}->{opt}, @_ );
	    
	    $this->{options}->{output} = $termOptions->{output};
	    $this->{wait} = $termOptions->{wait};  
	    delete $termOptions->{output};
	    
	    ## Emit the terminal options line for this terminal.
	    $this->{options}->{terminal} = join(" ", ($terminal, _emitOpts( $termOptions, $termTab->{$terminal}->{opt} )));
	    $this->{terminal} = $terminal;
	    $this->{mouse} = $termTab->{$terminal}->{mouse} || 0;
	} else {
	    barf "PDL::Graphics::Gnuplot doesn't support the device '$terminal', sorry\n\n     Run PDL::Graphics::Gnuplot::terminfo() for a list of devices.\n\n";
	}
    }        

    return $this;
}

##############################
# DESTROY - required to make sure the subprocess is gone.
# (no POD since it's not part of the usual API)

sub DESTROY
{
  my $this = shift;

  _killGnuplot($this);
}


=head2 close - close gnuplot process (actually just a synonym for restart)

=for ref

Some of the gnuplot terminals (e.g. pdf) don't write out a file
promptly.  The close method closes the associated gnuplot subprocess,
forcing the file to be written out.  It is implemented as a simple
restart operation.

The object preserves the plot state, so C<replot> and similar methods
still work with the new subprocess.

=cut

sub close
{
    my $this = shift;
    restart($this);
}

=head2 restart - restart the gnuplot backend for a plot object

=for usage

    $w->restart();
    PDL::Graphics::Gnuplot::restart();

=for ref

Occasionally the gnuplot backend can get into an unknown state.  
C<reset> kills the gnuplot backend and starts a new one, preserving
state in the object.  (i.e. C<replot> and similar functions work even
with the new subprocess).

Called with no arguments, C<restart> applies to the global plot object.

=cut

# reset - tops and restarts the underlying gnuplot process for an object
*grestart = \&restart;
sub restart {
    my $this = _obj_or_global(\@_);
    my $dumpswitch = shift;
    my $localdumpvar = $this->{options}->{dump};
    {
	# We restart the process when the dump option is switched on or off.
	# Since _killGnuplot uses _printGnuplotPipe, we have
	# to hold the old state briefly while the old process is killed.
	local($this->{options}->{dump}) = 
	    ($dumpswitch ? $this->{dumping} : $localdumpvar);
	
	_killGnuplot($this);
    }
    # When starting Gnuplot we use the {options}->{dump} flag as it should be.
    _startGnuplot($this,'main');
    _startGnuplot($this,'syntax') if($check_syntax);
    $this->{options}->{multiplot} = 0;
    undef $PDL::Graphics::Gnuplot::last_plotcmd;
    undef $PDL::Graphics::Gnuplot::last_testcmd;
}


=head2 reset - clear all state from the gnuplot backend

=for usage
   
    $w->reset()

=for ref

Clears all plot option state from the underlying object.  All plot
options except "terminal", "termoptions", "output", and "multiplot"
are cleared.  This is similar to the "reset" command supported by
gnuplot itself.


=cut
*greset = \*reset;
sub reset {
    my $this = _obj_or_global(\@_);
     for my $k(keys %{$this->{options}}) {
	unless ( $k =~ m/(terminal|output|termoptions|multiplot)/ ) {
	    delete $this->{options}->{$k};
	}
    }
    my $checkpointMessage;
    if($check_syntax) {
	_printGnuplotPipe( $this, "syntax", "reset\n");
	$checkpointMessage = _checkpoint($this,"syntax");
    }
    _printGnuplotPipe($this, "main", "reset\n");
    $checkpointMessage = _checkpoint($this, "main");
    
    $this->{replottable} = 0;
    delete $this->{last_plot};
    return $this;
}


##############################
# 
# Options setting routines
# 

=head2 options - set/get persistent plot options for a plot object

=for usage

  $w = new PDL::Graphics::Gnuplot();
  $w->options( globalwith=>'lines' );
  print %{$w->options()};

=for ref
  
The options method parses plot options into a gnuplot object on a
cumulative basis, and returns the resultant options hash.

If called as a sub rather than a method, options() changes the 
global gnuplot object.

=cut

*option = \&options;
sub options {
    my($me) = _obj_or_global(\@_);
    $me->{options} = {} unless defined($me->{options});
    _parseOptHash($me->{options}, $pOpt, @_);
    if($me->{last_plot} && $me->{last_plot}->{options}) {
	_parseOptHash($me->{last_plot}->{options}, $pOpt, @_);
    }
    return $me->{options};
}

######################################################################
######################################################################
#
# plot - the main API function to generate a plot. 

=head2 gplot - plot method exported by default (synonym for "PDL::Graphics::Gnuplot::plot")

=head2 plot - method to generate a plot

=for ref

This is the main plotting routine in PDL::Graphics::Gnuplot.

Each C<plot()> call creates a new plot from whole cloth, either creating
or overwriting the output for that device.

If you want to add features to an existing plot, use C<replot>.  

=for usage

 $w=gpwin();
 $w->plot({temp_plot_options},                 # optional
      curve_options, data, data, ... ,      # curve_options are optional for the first plot
      curve_options, data, data, ... ,
       {temp_plot_options});

Most of the arguments are optional.

All of the extensive array of gnuplot plot styles are supported, including images and 3-D plots.

=for example

 use PDL::Graphics::Gnuplot qw(plot);
 my $x = sequence(101) - 50;
 plot($x**2);

See main POD for PDL::Graphics::Gnuplot for details.

You can pass plot options into plot as either a leading or trailing hash ref, or both. 
If you pass both, the trailing hash ref is parsed last and overrides the leading hash.

For debugging and curiosity purposes, the last plot command issued to gnuplot
is maintained in a package global: C<$PDL::Graphics::Gnuplot::last_plotcmd>.

=cut

*gplot = \&plot;
sub plot
{
    barf( "Plot called with no arguments") unless @_;

    my $this = _obj_or_global(\@_);

    ##############################
    # Parse optional plot options - must be an array or hash ref, if present.
    # Cheesy but hopefully effective method (from Dima): parse as plot options
    # and if that throws an error treat 'em as curve options instead.
    #
    # This is additionally complicated by the desire to make these *temporary*
    # options -- so we don't accumulate the options in the main object options
    # hash.
    # 
    # The temporariness is accomplished by localizing $this->{options} and replacing
    # it with either itself or the parsed copy of itself.
    #
    #
    # As an additional DWIM to make Dima happy, we parse initial options as plot
    # options until encountering something that could conceivably be a curve option -
    # whereupon we switch to curve options.  The DWIMming is done by checking individual
    # option names to see if they (A) are NOT curve options and (B) are plot options.
    # We snarf up all such options and put 'em into a hash ref like they should have been.
    {
	my $dwim_plot_options = [];
	while( 0+@_ and !(ref $_[0]) ) {
	    my ($kk,$knum);

	    ($kk,$knum) = eval { _expand_abbrev($_[0], $cOpt->[1], $cOpt->[2]) };

	    if($@) {
		($kk,$knum) = eval { _expand_abbrev($_[0], $pOpt->[1], $pOpt->[2]) };

		if(!$@) {
		    # It's a plot option and not a curve option -- pull it, and its argument, from the arg list and put them 
		    # into $dwim_plot_options.
		    push(@{$dwim_plot_options}, shift);
		    push(@{$dwim_plot_options}, shift);
		} else {
		    last;
		}
	    } else {
		last;
	    }
	}
	if( 0+@{$dwim_plot_options} ) {
	    unshift(@_, $dwim_plot_options);
	}
    }

    # If we're replotting, start with the last_plot options - which may not be "persistent" in the
    # object but persist in the last_plot stored state.
    # 
    # *but* if we're replotting we have to preserve the current terminal, *not* the last terminal.
    my $o;
    if($this->{replotting}) {
	$o = $this->{last_plot}->{options};
	$o->{terminal} = $this->{options}->{terminal};
	$o->{output}   = $this->{options}->{output};
    } else {
	$o = $this->{options};
    }


    # Now parse the initial hash of plot options (if there is one)
    if(  (ref $_[0]) =~ m/^(HASH|ARRAY)/ ) {
	my $oo = dclone($o);
	eval { _parseOptHash( $oo, $pOpt, $_[0] ); };
	if($@ =~ m/^No /) {
	    # Found an unrecognized keyword -- clear the error and keep going.
	    # (not a set of plot options)
	    $@ = "";
	} elsif($@) {
	    # Some other actual exception -- pass it down the line.  Oops.
	    barf $@ . "   (while parsing presumed extra plot options at start of plot command)\n";
	} else {
	    # worked!
	    $o = $oo;
	    shift @_;  # pull argument off the start.
	}
    }

    # Now look for and parse a trailing hash of plot options (if there is one)
    if( $#_ >= 1  and   ((ref $_[-1])=~ /^(HASH|ARRAY)/)) {
	my $oo = dclone($o);
	eval { _parseOptHash( $oo, $pOpt, $_[-1] ); };
	if($@ =~ m/^No /) {
	    # Found an unrecognized keyword -- clear the error and keep going.
	    # (not a set of plot options)
	    $@ = "";
	} elsif($@) {
	    # Some other actual exception -- pass it down the line.  Oops.
	    barf $@ . "   (while parsing presumed extra plot options at end of plot command)\n";
	} else {
	    # worked!
	    $o = $oo;
	    pop @_;  # pull argument off the end.
	}
    }

    #  Localize the options...
    local($this->{options}) = $o;

    # Make sure to reset the palette to the gnuplot default if it's not set here
    $this->{options}->{palette} = [] unless($this->{options}->{palette});

    # If we're replotting, then any remaining arguments need to be put
    # *after* the arguments that we used for the last plot.  
    if($this->{replotting}) {
	unless(UNIVERSAL::isa($_[0],'PDL')) {
	    @_ = (@{$this->{last_plot}->{args}},@_);
	} else {
	    @_ = (@{$this->{last_plot}->{args}},{},@_);
	}

    }

    # Store the current arguments into the state array for next time.
    # (This has to be done here because plot options need to be stripped out first).
    # 
    # Because of all the local-variable shenanigans with overlain configs for this and that,
    # we unfortunately have to make a deep copy of the plot options for the last_plot.
    # The variables we deliberately do *not* deep copy, in case someone wants to use the
    # modify-and-replot trick that is in the gnuplot documentation.  (That trick uses
    # file modification, but in-place modification of PDLs "feels right" too)
    # 
    # We don't store the arguments if we're carrying the "ephemeral" flag - that is
    # so we can do ephemeral markup of plots, without adding to the replot list.
    unless($this->{ephemeral}) {
	$this->{last_plot}->{args}  = [@_];
	$this->{last_plot}->{options} = dclone($this->{options});
    }

    # Now parse the rest of the arguments into chunks.
    # parseArgs is a nested sub at the bottom of this one.
    my($chunks, $Ncurves) = parseArgs($this, @_);
    
    if( scalar @$chunks == 0)
    { barf "plot() was not given any data"; }
    
    ##############################
    # 
    # Now generate the plot command.
    # This is complicated by the need to generate two separate commands --
    # the main command (which goes into $plotcmd), and a separate test command
    # that is intended to check syntax (and goes into $testcmd).
    # 
    # We start by emitting the options string (and re-emitting it with the dumb 
    # terminal, for the test command), then emitting a mock-up of each 
    # chunk's plot/curve arguments into a single "plot" command line.  This first
    # line doesn't contain the data specifier, only a fence string.
    # 
    # Then we cut up the command line into pieces at the fences, so that we can assemble the 
    # data specifiers and build a complete command line.
    #
    
    ##########
    # Check binary mode operation.  We normally let everything default to binary, but 
    # if certain bug-triggering conditions are identified we switch to ASCII.  This is
    # the "global" mode calculation, which can be overridden on a per-chunk basis.

    my $binary_mode = $this->{options}->{binary};
    unless(defined $binary_mode) {

	# The user didn't explicitly set binary or non-binary mode.  Try to guess.
	if($this->{early_gnuplot}) {
	    # Early gnuplot - ASCII mode only (by default)
	    $binary_mode = 0;
	} else {

	    # Late-model gnuplot - binary for non time format plots, ASCII for time plots.
	    # (Note: some transfer formats force binary transfer)

	    my $using_times = 0;
	    for my $k( qw/x x2 y y2 z cb/ ) {
		if($this->{options}->{$k."data"} and $this->{options}->{$k."data"} =~ m/time/) {
		    $using_times = 1;
		    last;
		}
	    }
	    $binary_mode = !$using_times;
	}
    }




    ##########
    # Figure per-curve binary/ASCII mode, and fix up some of the option defaults based on context.  
    # In particular, gnuplot 4.4-4.6 don't handle image scaling correctly, so unless an xrange/yrange 
    # is specified we have to take care of it ourselves.  
    
    my ($cbmin,$cbmax) = (undef, undef);
    for my $i(0..$#$chunks) {

	# Allow global binary/ASCII flag to be overridden by per-curve binary/ASCII flag
	$chunks->[$i]->{binaryCurveFlag} = $chunks->[$i]->{binaryWith} // $binary_mode;

	# Everything else is an image fix
	next if( $chunks->[$i]->{cdims} != 2 );
	
	# Fix up gnuplot ranging bug for images
	if(defined($this->{options}->{xrange}) and !defined($chunks->[$i]->{options}->{xrange})) {
	    $chunks->[$i]->{options}->{xrange} = $this->{options}->{xrange};
	}

	if(defined($this->{options}->{yrange}) and !defined($chunks->[$i]->{options}->{yrange})) {
	    $chunks->[$i]->{options}->{yrange} = $this->{options}->{yrange};
	}

	unless( $i or 
		$chunks->[$i]->{options}->{xrange} or
		$chunks->[$i]->{options}->{yrange}
	    ) {

	    # Neither curve nor plot option has been set.  
	    if($chunks->[$i]->{ArrayRec} eq 'array') {
		# Autorange using matrix locations -- pixels lop over the edge by 0.5 on bottom and top for
		# image data, but not at all for vector data
		if($chunks->[$i]->{imgFlag}) {
		    $chunks->[$i]->{options}->{xrange} = [ -0.5, $chunks->[$i]->{data}->[0]->dim(1) - 0.5 ];
		    $chunks->[$i]->{options}->{yrange} = [ -0.5, $chunks->[$i]->{data}->[0]->dim(2) - 0.5 ];
		} else {
		    # Not an image - just use the minmax, and don't pad
		    $chunks->[$i]->{options}->{xrange} = [ 0, $chunks->[$i]->{data}->[0]->dim(1) - 1 ];
		    $chunks->[$i]->{options}->{yrange} = [ 0, $chunks->[$i]->{data}->[0]->dim(2) - 1 ];
		}
	    } else {
		# Autorange using x and y ranging -- sleaze out of matching gnuplot's algorithm by
		# calculating dx and dy.
		my($xmin,$xmax) = $chunks->[$i]->{data}->[0]->slice("(0)")->minmax;
		my($ymin,$ymax) = $chunks->[$i]->{data}->[0]->slice("(1)")->minmax;
		
		if($chunks->[$i]->{imgFlag}) {
		    my $dx = ($xmax-$xmin) / $chunks->[$i]->{data}->[0]->dim(1) * 0.5;
		    $chunks->[$i]->{options}->{xrange} = [$xmin - $dx, $xmax + $dx];
		    
		    my $dy = ($ymax-$ymin) / $chunks->[$i]->{data}->[0]->dim(2) * 0.5;
		    $chunks->[$i]->{options}->{yrange} = [$ymin - $dy, $ymax + $dy];
		} else {
		    # Not an image - just use the minmax, and don't pad
		    $chunks->[$i]->{options}->{xrange} = [$xmin,$xmax];
		    $chunks->[$i]->{options}->{yrange} = [$ymin,$ymax];
		}
	    }
	}
	
	# Fix up gnuplot color scaling bug/misfeature for RGB images
	# Here, we accumulate min/max color ranges across *all* imagelike chunks.
	if(!defined( $this->{options}->{cbrange} )) {
	    my $with = $chunks->[$i]->{options}->{with}->[0];

	    my $slice = "-1";
	    $slice = "-3:-1" if($with eq 'rgbimage');
	    $slice = "-4:-2" if($with eq 'rgbalpha');

	    my $bolus = $chunks->[$i]->{data}->[0]->slice($slice);

	    my ($cmin, $cmax) = $bolus->minmax;
	    $cbmin = $cmin if( !defined($cbmin)   or    $cbmin > $cmin );
	    $cbmax = $cmax if( !defined($cbmax)   or    $cbmax < $cmax );
	}
    }

    ##############################
    # Fix up cbrange if necessary.  We use the same localization trick
    # as for the whole options hash, only this time on just the single
    # keyword (in case we're not using a dcloned copy of the hash).
    $o = $this->{options}->{cbrange};
    local($this->{options}->{cbrange});
    if( defined($cbmin)   or   defined($cbmax) ) {
	$this->{options}->{cbrange} = [$cbmin, $cbmax];
    } else {
	$this->{options}->{cbrange} = $o;
    }

    ##############################
    # Since we accept axis ranges as curve options, but they are only
    # allowed in the first curve of a single multi-curve plot, we
    # don't allow ranges in later curves to be emitted.  
    { 
	my $rangeflag = 0;
	for my $i(1..$#$chunks) {
	    my $h = $chunks->[$i]->{options};
	    for my $k( qw/xrange yrange zrange trange/ ) {
		if(defined $h->{$k}) {
		    delete $h->{$k};
		    $rangeflag++;
		}
	    }
	}
	print STDERR "plot: WARNING: range specifiers aren't allowed as curve options after the first\ncurve.  I ignored $rangeflag of them. (You can also use plot options for ranges)\n"
	    if($rangeflag);

#	for my $k(qw/xrange yrange zrange trange/) {
#	    print STDERR "Warning: curve option $k overriding plot option $k\n"
#		if(exists($this->{options}->{$k})  and  exists($chunks->[0]->{options}->{$k}));
#	}
    }



    ##############################
    # If we're working with time data, and timefmt isn't set, then default it to '%s'.
    $this->{options}->{timefmt} = '%s'
	if ( !defined($this->{options}->{timefmt}) and  
	     grep { ($this->{options}->{$_."data"} // "") =~ m/^time/i }  qw/x x2 y y2 z cb/ );
    
    ##########
    # Merge in any temporary options that have been set by the argument parsing.
    # (e.g. prefrobnicators can set plot options via $this->{tmp_options}).  This is OK since 
    # we've already localized $this->{options}.
    if(exists($this->{tmp_options})) {
	for my $k(%{$this->{tmp_options}}) {
	    $this->{options}->{$k} = $this->{tmp_options}->{$k};
	}
    }

    ##########
    # Emit the plot options lines that go above the plot command.  We do this 
    # twice -- once for the main plot command and once for the syntax test.
    my $plotOptionsString = _emitOpts($this->{options}, $pOpt);
    my $testOptionsString;
    if($check_syntax){
	local($this->{options}->{terminal}) = "dumb";
	local($this->{options}->{output}) = ' ';
	$testOptionsString = _emitOpts($this->{options}, $pOpt);
    }

    ##########
    # Generate the plot command with the fences in it instead of data specifiers. 
    # (The fences are emitted in _emitOpts and contained in the global $cmdFence)
    my $plotcmd =  ($this->{options}->{'3d'} ? "splot " : "plot ") . 
	join( ", ", 
	      map { 
		  _emitOpts($chunks->[$_]->{options}, $cOpt, $this);
	      } (0..$#$chunks)
	);

    ##########
    # Break up the plot command so we can insert data specifiers in each location
    my @plotcmds = split /$cmdFence/, $plotcmd;
    if(@plotcmds != @$chunks+1) {
	barf "This should never happen, but it did.  That's odd.  I give up.";
    }

    ##########
    # Rebuild the plot command by inserting the format string and data spec for each piece,
    # instead of the placeholder fence strings.
    #
    # Image-style formats use binary matrix format rather than ordinary binary format and must
    # be handled slightly differently.
    #
    my $testcmd;
    {
	my $fl = shift @plotcmds;
	$plotcmd =  $fl;
	$testcmd =  $fl if($check_syntax);
    }

    for my $i(0..$#plotcmds){
	my($pchunk, $tchunk);
	
	if( $chunks->[$i]->{cdims} == 2 ) {
	    # It's an image -- always use binary to push the image out.

	    unless( $binary_mode ) {
		print STDERR "WARNING: images are generally too large for ASCII.  Using binary instead.\n";
	    }

	    # The map statement ensures the main and test cmd get identical sprintf templates.
	    my $fstr = "%double" x $chunks->[$i]->{tuplesize};
	    ($pchunk, $tchunk) = map {
		sprintf(' "-" binary %s=(%s) format="%s" %s',
			$chunks->[$i]->{ArrayRec},
			$_,
			$fstr, 
			$plotcmds[$i]);
	    } ( join(",", ($chunks->[$i]->{data}->[0]->slice("(0)")->dims)),
		join(",", (("1") x ($chunks->[$i]->{data}->[0]->ndims - 1)))
	      );
	    # Mock up test data - just a single data point for each (8 is the size of an IEEE double)
	    $chunks->[$i]->{testdata} = "." x ($chunks->[$i]->{tuplesize} * 8);

	} else {
	    # It's a non-image plot.  Calculate whether binary or ASCII output.
	    # First, check the per-chunk flag (if set).  If it's not, then 
	    # use the global flag.

	    if( $chunks->[$i]->{binaryCurveFlag} ) {
		my $fstr = "%double" x $chunks->[$i]->{tuplesize};
		my $first = $chunks->[$i]->{data}->[0];
		# The specifiers are identical, except that one gets a length of 1 and the other gets
		# the correct length.   The map statement ensures the main and test cmd get identical 
		# sprintf templates.
		($pchunk, $tchunk) = map {
		    sprintf(" '-' binary %s=(%d) format=\"%s\" %s",
			    $chunks->[$i]->{ArrayRec},
			    $_, 
			    $fstr, 
			    $plotcmds[$i]);
		} (  ((ref($first) eq 'ARRAY') ? 0+@{$first} : $first->dim(0))  , 1);
		
		# test data is a string containing the data to send -- just garbage. Use '.' to aid 
		# byte counting in the test string.
		$chunks->[$i]->{testdata} = $testdataunit_binary x ($chunks->[$i]->{tuplesize});
	    } else {		
		# ASCII transfer has been specified - plot command is easier, but the data are in ASCII.
		$pchunk = $tchunk =   " '-' ".$plotcmds[$i];
		$chunks->[$i]->{testdata} = " 1 " x ($chunks->[$i]->{tuplesize}) . "\ne\n";
	    }
	}

	$plotcmd .= $pchunk;
	$testcmd .= $tchunk if($check_syntax);

    }
	
    $plotcmd .= "\n";


    my $postTestplotCheckpoint = 'xxxxxxx Plot succeeded xxxxxxx';
    my $print_checkpoint = "; print \"$postTestplotCheckpoint\"";
    $testcmd .= "$print_checkpoint\n" if($check_syntax);


    ##########
    # Put data and final checkpointing on the test command
    $testcmd .= join("", map { $_->{testdata} } @$chunks) if($check_syntax);

    # Stash this plot command in the debugging variable

    our $last_plotcmd = $plotOptionsString.$plotcmd;
    our $last_testcmd = $plotOptionsString.$testcmd if($check_syntax);

    if($PDL::Graphics::Gnuplot::DEBUG) {
	print "plot command is:\n$plotcmd\n";
    }

    #######
    # The commands are assembled.  Now test 'em by sending the test command down the pipe.
    my $checkpointMessage;
    if($check_syntax) {
	_printGnuplotPipe( $this, "syntax", $plotOptionsString.$testcmd );
	$checkpointMessage = _checkpoint($this,"syntax");
	
	if(defined $checkpointMessage && $checkpointMessage !~ /^$postTestplotCheckpoint/m)
	{
	    $checkpointMessage =~ s/$print_checkpoint//;
	    barf "Gnuplot error: \"$checkpointMessage\" while syntax-checking the plot cmd \"$testcmd\"";
	}
    }


    ##############################
    ##############################
    ##### Send the PlotOptionsString 
    _printGnuplotPipe( $this, "main", $plotOptionsString);
    my $optionsWarnings = _checkpoint($this, "main", {printwarnings=>1});
    if($optionsWarnings) {
	if($MS_io_braindamage) {
	    # MS Windows can yield some chatter on the line, and it's not necessarily an
	    # error.  So we don't barf, we only warn. Blech.
	    print STDERR "WARNING: the gnuplot process gave some unexpected chatter:\n$optionsWarnings\n\n";
	} else {
	    barf( "The gnuplot process returned an error during plot setup:$optionsWarnings\n\n");
	}
    }
    
    ##############################
    ##############################
    ##### Finally..... send the actual plot command to the gnuplot device.
    _printGnuplotPipe( $this, "main", $plotcmd);
    $this->{last_plot}->{command} = $plotcmd;

    my $chunkno = 0;
    for my $chunk(@$chunks){
	my $p;

	if($chunk->{cdims}==2) {
	    # Currently all images are sent binary
	    $p = $chunk->{data}->[0]->double->copy;
	    $last_plotcmd .= " [ ".length(${$p->get_dataref})." bytes of binary image data ]\n";
	    _printGnuplotPipe($this, "main", ${$p->get_dataref},1);

	} elsif( $chunk->{binaryCurveFlag}  ) {
	    # Send in binary if the binary flag is set.
	    $p = pdl(@{$chunk->{data}})->mv(-1,0)->double->copy;
	    $last_plotcmd .= " [ ".length(${$p->get_dataref})." bytes of binary data ]\n";
	    _printGnuplotPipe($this, "main", ${$p->get_dataref},1);

	} else {
	    # Not in binary mode - send this chunk in ASCII.  Each line gets one tuple, followed
	    # a line with just "e".

	    if(ref $chunk->{data}->[0] eq 'PDL') {
		# It's a collection of PDL data only.
		$p = pdl(@{$chunk->{data}})->slice(":,:"); # ensure at least 2 dims
		$p = $p->mv(-1,0);                         # tuple dim first, rows second

		$last_plotcmd .= " [ ".$p->dim(1)." lines of ASCII data ]\n";
		# Emit $p as a collection of " " separated lines, followed by "e".
		_printGnuplotPipe($this,
				  "main",
				  join("\n", map { join(" ", $_->list) } $p->dog)  .  "\ne\n",
				  1
		    );
	    } else {
		# It's a collection of list ref data only.  Assemble strings.
		my $data = $chunk->{data};
		my $last = $#{$chunk->{data}->[0]};
		my $s = "";

		for my $i(0..$last) {
		    for my $j(0..$#$data){
			my $elem = $data->[$j]->[$i];
			if($elem =~ m/[\s\"]/) {    # element contains whitespace or quotes
			    $elem =~ s/\"/\\\"/g;   # Escape quotes
			    $elem =~ s/[\n\r]/ /g;  # Remove any newlines or returns
			    $elem = "\"$elem\"";    # quote the element
			}
			$s .= "$elem ";             # append the element to the output string.
		    }
		    $s .= "\n";                     # add newline
		}
		$s .= "e\n";                        # end the command
		_printGnuplotPipe($this, "main", $s, 1);
	    }
	}
    }
	
    my $plotWarnings = _checkpoint($this, "main", {printwarnings=>1});
    if($plotWarnings) {
	if($MS_io_braindamage) {
	    # MS Windows can yield some chatter on the line, and it's not necessarily an
	    # error.  So we don't barf, we only warn. Blech.
	    print STDERR "WARNING: the gnuplot process gave some unexpected chatter:\n$plotWarnings\n\n";
	} else {
	    barf("the gnuplot process returned an error during plotting: $plotWarnings\n\n");
	}
    }

    if($MS_io_braindamage) {
	_printGnuplotPipe($this,"main", "\r\n"x256); # Send a bunch of return carriages to get a prompt.
	_checkpoint($this,"main",{printwarnings=>1});
    }

    ##############################
    # Finally, finally ...  send any required cleanup commands.  This 
    # starts with {bottomcmds} and includes several things we don't want to persist,
    # but that do by default.

    my $cleanup_cmd = "";
    {
	my $bc = $this->{options}->{bottomcmds};
	if(defined($bc)){
	    $cleanup_cmd = (  (ref($bc) eq 'ARRAY') ?
			      join( "\n", @$bc,"" ) :
			      $bc."\n"
		);
	}

    } 

    $cleanup_cmd .= "set size noratio\nset view noequal\nset view 60,30,1.0,1.0\n";

    # Mark the gnuplot as replottable - we now have a full set of plot parameters stashed away.
    $this->{replottable} = 1;

    if($check_syntax) {
	$PDL::Graphics::Gnuplot::last_testcmd .= $cleanup_cmd;
	_printGnuplotPipe($this, "syntax", $cleanup_cmd);
	$checkpointMessage= _checkpoint($this, "syntax", {printwarnings=>1});
	if($checkpointMessage) {
	    barf "Gnuplot error: \"$checkpointMessage\" after syntax-checking cleanup cmd \"$cleanup_cmd\"\n";
	}
    }
    
    $PDL::Graphics::Gnuplot::last_plotcmd .= $cleanup_cmd;
    _printGnuplotPipe($this, "main", $cleanup_cmd);
    $checkpointMessage= _checkpoint($this, "main", {printwarnings=>1});
    if($checkpointMessage) {
	if($MS_io_braindamage) {
	    # MS Windows can yield some chatter on the line, and it's not necessarily an
	    # error.  So we don't barf, we only warn.  Blech.
	    print STDERR "WARNING: the gnuplot process gave some unexpected chatter after plot cleanup:\n$checkpointMessage\n";
	} else {
	    barf "Gnuplot error: \"$checkpointMessage\" after sending cleanup cmd \"$cleanup_cmd\"\n";
	}
    }
    
    # read and report any warnings that happened during the plot
    return $plotWarnings;

    #####################
    # 
    # parseArgs - helper sub nested inside plot
    # 
    # This breaks out the parsing of the plot arguments. 
    # 
    # Each chunk of data to plot appears in the argument list as 
    #      plot(options, options, ..., data, data, ....). 
    # The options are a hashref or an inline hash and also serve as delimiters between 
    # chunks of data. 
    #
    # Curve options, with the exception of "legend", are accumulated - each set
    # is used as the default value of the same option for the next one.
    # 
    # The data arguments are one-argument-per-tuple-element, but higher 
    # dims can be used for threading.  Plot elements that are to be treated 
    # as 1-D (non-image) data can be threaded over -- so, e.g., you can pass in 
    # a 50 PDL (as X) and a 50x3 PDL (as Y) and you'll get three separate plots with
    # the same options.  As a special case, you can pass an array ref into the 
    # "legend" or "color" options in that case, and thereby specify a different legend/color 
    # for each of those threaded plots.
    #
    sub parseArgs
    {
	my $this = shift;


	##############################
	# Parse curve option / data chunks.

	my @args = @_;
	
	my $is3d = (defined $this->{options}->{'3d'}) ? $this->{options}->{'3d'} : 0;
	my $ND = (('2D','3D')[!!$is3d]);  # mainly for error messages
	my $spec_legends = 0;
	
	# options are cumulative except the legend (don't want multiple curves named
	# the same). This is a hashref that contains the accumulator.
	my $lastOptions = {};
	
	my @chunks;
	my $Ncurves  = 0;
	my $argIndex = 0;
	
	while($argIndex <= $#args)
	{
	    # First, I find and parse the options in this chunk
	    # Array refs are allowed in some curve options, so, but only as values of key/value
	    # pairs -- so any list refs glommed in with a bunch of other refs are data.
	    # This is cheesy because (e.g.) "xrange=>[5],[0,1,2]" works but "xrange=>5,[0,1,2]" does not.
	    # The only way to get every single case like this is to actually parse a chunk at a time before
	    # figuring out nextDataIdx.  But those forms are deprecated anyway - better to use 
	    # a hash ref when possible.
	    my $nextDataIdx = first { (ref $args[$_] ) and 
					  (  (ref($args[$_]) =~ m/PDL/) or 
					     (ref($args[$_]) =~ m/ARRAY/ and ref($args[$_-1]))
					  )
					  
	    } $argIndex..$#args;

	    last if !defined $nextDataIdx; # no more data. done.
	    
	    # I do not reuse the curve legend, since this would result in multiple
	    # curves with the same name.
	    map { delete $lastOptions->{$_} } qw/legend xrange yrange zrange x2range y2range/;

	    my %chunk;
	    $chunk{options} = dclone( 
		_parseOptHash( $lastOptions, $cOpt, @args[$argIndex..$nextDataIdx-1] )
		);

	    $chunk{options}->{data}="dummy"; # force emission of the data field

	    # Find the data for this chunk...
	    $argIndex         = $nextDataIdx;
	    my $nextOptionIdx = first { (!(ref $args[$_])) or 
					(ref $args[$_]) !~ m/^(PDL|ARRAY)$/} $argIndex..$#args;
	    $nextOptionIdx = @args unless defined $nextOptionIdx;

	    # Make sure we know our "with" style...
	    unless($chunk{options}{with}) {
		$chunk{options}{with} = $this->{options}->{'globalwith'} // ["lines"];
	    }

	    # validate "with" and get imgFlag and tupleSizes.
	    # First, unpack the "with" -- we accept a list of with parameters, but also
	    # unpack them if they are supplied as a single smushed-together string.
	    our $plotStyleProps; # declared below
	    my @with;
	    if(@{$chunk{options}{with}}==1) {
		@with = split /\s+/,$chunk{options}{with}->[0];
		@{$chunk{options}{with}} = @with;
	    } else {
		@with = @{$chunk{options}{with}};
	    }
	    # Look for the plotStyleProps entry.  If not there, try cleaning up the with style
	    # before giving up entirely.
	    unless( exists( $plotStyleProps->{$with[0]}->[0] ) ) {
		our $plotStylesAbbrevs;

		# Try pluralizing and lc'ing if that works...
		if($with[0] !~ m/s$/i  and  exists( $plotStyleProps->{lc $with[0].'s'} ) ) {
		    $with[0] = lc $with[0].'s';
		    $chunk{options}{'with'}[0] = $with[0];
		} else {
		    # nope.  throw a fit.
		    barf "invalid plotstyle 'with ".($with[0])."' in plot\n";
		}
	    }

	    my $psProps = $plotStyleProps->{$with[0]};

	    # Extract the data objects from the argument list.  
	    # They should all be either PDLs or array refs.
	    my @dataPiddles = @args[$argIndex..$nextOptionIdx-1] ;


	    # Some plot styles (currently just "fits") are implemented via a 
	    # prefrobnicator that processes the data.
	    if( $psProps->[ 4 ] ) {
		@dataPiddles = &{ $psProps->[4] }( \@with, $this, \%chunk, @dataPiddles );
		$psProps = $plotStyleProps->{$with[0]};
	    }


	    # Image flag and base tuplesizes allowed for this plot style...
	    my $tupleSizes     = $psProps->[ !!$is3d ];  # index is 0 or 1 depending on truth of 3D flag
	    my $imgFlag        = $psProps->[ 2 ];        
	    $chunk{binaryWith} = $psProps->[ 3 ]; 
	    
	    # Reject disallowed plot styles
	    unless(ref $tupleSizes) {
		barf "plotstyle 'with ".($with[0])."' isn't valid in $ND plots\n";
	    }

	    # Additional columns are needed for certain 'with' modifiers. Figure 'em, cheesily: each
	    # palette or variable option to 'with' needs an additional column.
	    my $ExtraColumns = 0;
	    map { $ExtraColumns++ } grep /(palette|variable)/,map { split /\s+/ } @with;
	    
	    ##############################
	    # Figure out what size of tuple we have, and check it against the tuple sizes we can take...
	    my $NdataPiddles = @dataPiddles;

	    # Check in case it was explicitly set [not normally needed, but still...]
	    if($chunk{options}->{tuplesize}) {
		if($NdataPiddles != $chunk{options}->{tuplesize}) {
		    barf "You specified a tuple size of ".($chunk{options}->{tuplesize})." but only $NdataPiddles columns of data\n";
		}
	    }

	    my (@tuplematch) = (grep ((abs($_)+$ExtraColumns == $NdataPiddles), @$tupleSizes));


	    if( @tuplematch ) {
		# Tuple sizes that require autogenerated dimensions require 'array'; all others
		# reqire 'record'.
		$chunk{ArrayRec} = ($tuplematch[0] < 0) ? 'array' : 'record';
	    } else {
		# No match -- barf unless you really meant it
		if($chunk{options}->{tuplesize}) {
		    $chunk{ArrayRec} = 'record';
		    print STDERR "WARNING: forced disallowed tuplesize with a curve option...\n";
		} else {
		    my $pl = ($NdataPiddles==1)?"":"s";
		    my $s = "Found $NdataPiddles PDL$pl for $ND plot type 'with ".($with[0])."', which needs ";
		    if(@$tupleSizes==0) {
			barf "Ouch! I'm never supposed to take this path.  Please report a bug.";
		    } elsif(@$tupleSizes==1) {
			$s .= abs($tupleSizes->[0]) + $ExtraColumns;
		    } else {
			$s .= "one of [".join(",",map { abs($_)+$ExtraColumns } @$tupleSizes)."]";
		    }
		    if($ExtraColumns) {
			my $pl = ($ExtraColumns==1)?"":"s";
			$s .= " (including the $ExtraColumns extra$pl from your 'with' options).\n";
		    } else {
			$s .= ".\n";
		    }
		    barf $s;
		}
	    }

	    ##############################
	    # Implicit dimensions in 3-D plots require imgFlag to be set...
	    my $cdims;
	    if($chunk{options}->{cdims}) {
		$cdims = $chunk{options}->{cdims};
		if($cdims==1 and $imgFlag) {
		    barf("You specified column dimension of 1 for an image plot type! Not allowed.");
		}
	    } else {
		$cdims = ($imgFlag or ( $is3d && $dataPiddles[0]->ndims >= 2 )) ? 2 : 1;

	    }

	    ##############################
	    # A little aside:  streamline the common optimization case -- 
	    # if the user specified "image" but handed in an RGB or RGBA image, 
	    # bust it up into components and update the 'with' accordingly.
	    if( $cdims==2 ) {
		if($chunk{options}->{with}->[0] eq 'image') {

		    my $dp = $dataPiddles[$#dataPiddles];

		    if($dp->ndims==3) {
			if($dp->dim(2)==3) {
			    $chunk{options}->{with}->[0] = 'rgbimage';
			    pop @dataPiddles;
			    push(@dataPiddles,$dp->dog);
			} elsif($dp->dim(2)==4) {
			    $chunk{options}->{with}->[0] = 'rgbalpha';
			    pop @dataPiddles;
			    push(@dataPiddles,$dp->dog);
			}
		    }
		}
	    }
	    $chunk{cdims} = $cdims;

	    $chunk{tuplesize} = @dataPiddles;
	    
	    @dataPiddles = matchDims( @dataPiddles );

	    # Make sure there is a using spec, in case one wasn't given
	    $chunk{options}->{using} = join(":",1..$chunk{tuplesize}) 
		unless exists($chunk{options}->{using});

	    # Check number of lines threaded into this tupleset; make sure everything 
	    # is consistent...
	    my $ncurves;

	    if($imgFlag){
		if($dataPiddles[0]->dims < 2) {
		    barf "Image plot types require at least a 2-D input PDL\n";
		}
	    }

	    # For the image case glom everything together into one 3-dimensional PDL, 
	    # pre-inverted so that the 0 dim runs across column.
	    if($cdims==2) {
		# Surfaces never get a label unless one is explicitly set
		$chunk{options}->{legend} = undef unless( exists($chunk{options}->{legend}) );
		$spec_legends = 1;

		my $p = pdl(@dataPiddles);

		# Coerce up to 3 dimensions, with (col, ix, iy).
		if( $p->dims == 2) {
		    $p = $p->dummy(0,1);
		} else {
		    $p = $p->mv(-1,0);
		}

		if( ($p->dims > 3) ) {
		    barf("PDL::Graphics::Gnuplot::plot: I can't make sense of this dimensional mix -- \n  I ended up with (".join("x",$p->dims).") data after combining everything. \n   (Did you mix list and PDL-stack formulations, or try to thread 2-D columns?)\n");
		}

		# Place the PDL onto the argument stack.
		@dataPiddles = ($p);

		$chunk{tuplesize} = $p->dim(0);
		$ncurves = 1;


		$chunk{data}      = \@dataPiddles;
		$chunk{imgFlag} = 1;
		push @chunks, \%chunk;

	    } elsif( (ref $dataPiddles[0]) eq 'PDL' ) {
		# Non-image case: check that the legend count agrees with the
		# number of curves we found, and break up compound chunks (with multiple 
		# curves) into separate chunks of one curve each.

		$ncurves = $dataPiddles[0]->slice("(0)")->nelem;

		# Speed bump for weird case
		our $bigthreads;
		if($ncurves >= 100 and !$bigthreads) {
		    print STDERR <<"FOO"
PDL::Graphics::Gnuplot: WARNING - you seem to be plotting $ncurves
curves in a single threaded collection.  This could be because you fed
in a 2-D (or higher) data set when you meant to plot a single curve.
If so, you may want to flatten your data and try again. (To disable
this message, set \$PDL::Graphics::Gnuplot::bigthreads to be true).
If you are trying to plot a surface, you might try setting 'trid=>1'
in the plot options.
FOO
		}

		if($chunk{options}->{legend} and 
		   @{$chunk{options}->{legend}} and 
		   @{$chunk{options}->{legend}} != $ncurves
		    ) {
		    my $ent = (0+@{$chunk{options}->{legend}} == 1) ? "y" : "ies";
		    my $pl = ($ncurves==1)?"":"s";
		    barf "Legend has ".(0+@{$chunk{options}->{legend}})." entr$ent; but ".($ncurves)." curve$pl supplied!";
		}

		# Ensure legend appears in the options parsing (to emit "notitle" if necessary)
		$chunk{options}->{legend} = undef unless(exists($chunk{options}->{legend}));


		$spec_legends = 1 if($chunk{options}->{legend});


		$chunk{tuplesize} = $NdataPiddles;

		if($ncurves==1) {
		    # The chunk is OK.
		    $chunk{data}      = \@dataPiddles;
		    push @chunks, \%chunk;
		} else {
		    # The chunk needs splitting, options and all.
		    for my $i(0..$ncurves - 1) {
			my $chk = dclone(\%chunk);
			$chk->{data} = [ map { $_->slice(":,($i)") } @dataPiddles ];
			
			if(exists($chk->{options}->{legend})) {
			    $chk->{options}->{legend} = [$chk->{options}->{legend}->[$i]];
			}
			
			push(@chunks, $chk);
		    }
		}
	    } else {
		# Non-image case, with array refs instead of PDLs -- we required the chunk to be
		# simple in matchDims, so just push it.
		$ncurves = 1;
		$chunk{data} = \@dataPiddles;
		$chunk{imgFlag} = 0;
		# Ensure legend appears in the options parsing (to emit "notitle" if necessary)
		$chunk{options}->{legend} = undef unless(exists($chunk{options}->{legend}));

		push @chunks, \%chunk;
	    }

	    $Ncurves += $ncurves;
	    $chunk{imageflag} = $imgFlag;

	    
	    $argIndex = $nextOptionIdx;
	}
	
	return (\@chunks, $Ncurves);
    } # end of ParseArgs nested sub


    ##########
    # matchDims: nested sub inside plot - kludge up thread style matching across 
    # the data arguments to a given chunk.
    sub matchDims
    {
	my @data = @_;

	my $nonPDLCount = 0;
	map { $nonPDLCount++ unless(ref $_ eq 'PDL') } @data;

	# In the case where all data are PDLs, we match dimensions.
	unless($nonPDLCount) {
	    # Make sure the domain and ranges describe the same number of data points,
	    # and that all PDLs have at least one dim.
	    #
	    # ( This is complicated by the need/desire to preserve threading rules.  Here, 
	    # we accumulate thread dimensions manually and then match 'em using dummy
	    # dimensions...  --CED )
	    my @data_dims = (1);  # ensure at least 1 dim with at least 1 element
	    
	    # Assemble the thread-rules dim list
	    for my $i(0..$#data) {
		my @ddims = $data[$i]->dims;
		for my $i(0..$#ddims) {
		    if( (!defined($data_dims[$i])) || ($data_dims[$i] <= 1) ) {
			$data_dims[$i] = $ddims[$i];
		    } 
		    elsif( ( $ddims[$i]>1) && ($ddims[$i] != $data_dims[$i] )) {
			barf "plot(): mismatched arguments in tuple (position $i)\n";
		    }
		}
	    }
	    
	    # Now pad each data element out, by slicing, to match the full dim list.  If the
	    # dim matches, mark a ':'; if not, put in the correct dummy dim to make it match.
	    # Don't bother slicing unless at least one dummy dim is needed.
	    for my $i(0..$#data) {
		my @ddims = $data[$i]->dims;
		my @s = ();
		my $slice_needed = 0;
		
		for my $id(0..$#data_dims) {
		    if((!defined($ddims[$id])) || !$ddims[$id]) {
			push(@s,"*$data_dims[$id]");
			$slice_needed = 1;
		    } 
		    elsif($data_dims[$id] == $ddims[$id]) {
			push(@s,":");
		    } 
		    elsif( $ddims[$id]==1 ) {
			push(@s,"(0), *$data_dims[$id]");
			$slice_needed = 1;
		    } else {
			# should never happen
			barf "plot(): problem with dim assignments. This is a bug."; # no newline
		    }
		}
		
		if($slice_needed) {
		    my $s = join(",",@s);
		    $data[$i] = $data[$i]->slice( join(",",@s) );
		}
	    }
	    return @data;
	} else {
	    # At least one of the data columns is a non-PDL.  Force them to be simple columns, and
	    # require exact dimensional match.
	    #
	    # Also, convert any contained PDLs to list refs.

	    my $nelem;
	    my @out = ();

	    for(@data) {
		barf "plot(): only 1-D PDLs are allowed to be mixed with array ref data\n"
		    if( (ref $_ eq 'PDL') and $_->ndims > 1 );

		if((ref $_) eq 'ARRAY') {
		    barf "plot(): row count mismatch:  ".(0+@$_)." != $nelem\n"
			if( (defined $nelem) and (@$_ != $nelem) );
		    $nelem = @$_;

		    for (@$_) {
			barf "plot(): nested references not allowed in list data\n"
			    if( ref($_) );
		    }

		    push(@out, $_);

		} elsif((ref $_) eq 'PDL') {
		    barf "plot(): nelem disagrees with row count: ".$_->nelem." != $nelem\n"
			if( (defined $nelem) and ($_->nelem != $nelem) );
		    $nelem = $_->nelem;

		    push(@out, [ $_->list ]);

		} else {
		    barf "plot(): problem with dim checking.  This should never happen.";
		}
	    }
	    
	    return @out;
	}
    } # end of matchDims (nested in plot)
}  # end of plot

######################################################################
######################################################################
#
# convenience wrappers for plot
#
##############################

=head2 replot - Replot the last plot (possibly with new arguments)

=for ref

C<replot> is similar to gnuplot's "replot" command - it allows you to
regenerate the last plot made with this object.  You can change the
plot by adding new elements to it, modifying options, or even (with the 
"device" method) changing the output device.  C<replot> takes the same
arguments as C<plot>.

If you give no arguments at all (or only a plot object) then the plot 
is simply redrawn.  If you give plot arguments, they are added to the 
new plot exactly as if you'd included them in the original plot 
element list, and maintained for subsequent replots.

(Compare to 'markup').

=cut

sub replot {
    my $this = _obj_or_global(\@_);
    if($this->{replottable}) {
	local($this->{replotting}) = 1;
	$this->plot(@_);
    } else {
	die "PDL::Graphics::Gnuplot::replot: you must have already plotted something!\n";
    }
}

=head2 markup - Add ephemeral markup to the last plot

=for ref

C<markup> works exactly the same as C<replot>, except that any 
new arguments are not added to the replot list - so you can 
add temporary markup to a plot and regenerate the plot later
without it.

=cut

sub markup {
    my $this = _obj_or_global(\@_);
    if($this->{replottable}) {
	local($this->{replotting}) = 1;
	local($this->{ephemeral}) = 1;
	$this->plot(@_);
    } else {
	die "PDL::Graphics::Gnuplot::markup: you must have already plotted something!\n";
    }
}
    
=head2 plot3d, splot

=for ref

Generate 3D plots. Synonyms for C<plot(trid =E<gt> 1, ...)>

=cut
*splot = \&plot3d;
sub plot3d {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'3d'}) = 1;
    plot($this,@_);
}

=head2 lines

=for ref

Generates plots with lines, by default. Shorthand for C<plot(globalwith =E<gt> 'lines', ...)>

=cut
*line = \&lines;
sub lines {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'globalwith'}) = ['lines'];
    plot($this,@_);
}

=head2 points

=for ref

Generates plots with points, by default. Shorthand for C<plot(globalwith =E<gt> 'points', ...)>

=cut

sub points {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'globalwith'}) = ['points'];
    plot($this,@_);
}

=head2 image

=for ref

Displays an image (either greyscale or RGB)

=cut

sub image {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'globalwith'}) = ["image"];
    plot($this, @_);
}

=head2 fits

=for ref

Displays a FITS image 

=cut

sub fits {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'globalwith'}) = ["fits"];
    plot($this,@_);
}
    
##############################
# Multiplot support

=head2 multiplot

=for example

 $a = (xvals(101)/100) * 6 * 3.14159/180;
 $b = sin($a);

 $w->multiplot(layout=>[2,2],"columnsfirst");
 $w->plot({title=>"points"},with=>"points",$a,$b);
 $w->plot({title=>"lines"}, with=>"lines", $a,$b);
 $w->plot({title=>"image"}, with=>"image", $a->(*1) * $b );
 $w->end_multi();

=for ref

The C<multiplot> method enables multiplot mode in gnuplot, which permits
multiple plots on a single pane.  Plots can be lain out in a grid,
or can be lain out freeform using the C<size> and C<origin> plot 
options for each of the individual plots.  

It is not possible to change the terminal or output device when in 
multiplot mode; if you try to do that, by setting one of those plot
options, PDL::Graphics::Gnuplot will throw an error.

The options hash will accept:

=over 3

=item layout - define a regular grid of plots to multiplot

C<layout> should be followed by a hash ref that contains at least
number of columns ("NX") followed by number of rows ("NY).  After
that, you may include any of the "rowsfirst", "columnsfirst",
"downwards", or "upwards" keywords to specify traversal order through
the grid.  Only the first letter is examined, so (e.g.) "down" or even
"dog" works the same as "downwards".

=item title - define a title for the entire page

C<title> should be followed by a single scalar containing the title string.

=item scale - make gridded plots larger or smaller than their allocated space

C<scale> takes either a scalar or a list ref containing one or two
values.  If only one value is supplied, it is a general scale factor
of each plot in the grid.  If two values are supplied, the first is an
X stretch factor for each plot in the grid, and the second is a Y
stretch factor for each plot in the grid.  

=item offset - offset each plot from its grid origin

C<offset> takes a list ref containing two values, that control placement
of each plot within the grid.

=back

=cut

# This table describes gnuplot option parsing for the multiplot command.
# Its format is the same as the $plotOptionsTable, below.

our $mpOptionsTable = {
    'layout' => [sub { my($old, $new, $h) = @_;
		       my ($nx,$ny);
		       my @dirs=("","");
		       if(!ref($new)) {
			   $nx = $ny = $new;
		       } elsif(ref($new) eq 'ARRAY') {
			   $new = [1] if(@$new == 0);
			   $nx = shift @$new;
			   $ny = (@$new) ? shift @$new : $nx;
			   while($_ = shift @$new) { # assignment
			       $dirs[0]="rowsfirst"    if(m/^r/i);
			       $dirs[0]="columnsfirst" if(m/^c/i);
			       $dirs[1]="downwards"    if(m/^d/i);
			       $dirs[1]="upwards"      if(m/^u/i);
			   }
		       } else {
			   barf "multiplot: layout option needs a scalar or array ref value\n";
		       }
		       return join(" ",("$ny,$nx",$dirs[0],$dirs[1]));
		 },
		 'cl',undef,1,''],
    'title' => ['s','cq',undef,2,''],
    'scale' => ['l','c,',undef,3,''],
    'offset'=> ['l','c,',undef,4,'']
};
our $mpOptionsAbbrevs = _gen_abbrev_list(keys %$mpOptionsTable);
our $mpOpt = [$mpOptionsTable, $mpOptionsAbbrevs, "multiplot option"];
		       
sub multiplot {
    my $this = _obj_or_global(\@_);
    my @params = @_;

    if($this->{options}->{multiplot}) {
	print STDERR "Warning: multiplot: object is already in multiplot mode!\n  Exiting multiplot mode first...\n";
	end_multi($this);
    } 

    my $mp_opts = _parseOptHash( undef, $mpOpt, @_ );

    # Assemble the command.  

    my $command = "set multiplot " . _emitOpts($mp_opts, $mpOpt) . "\n";
    my $preamble = _emitOpts({ 'terminal'   => $this->{options}->{terminal}, 
			       'output'     => $this->{options}->{output}, 
			       'termoption' => $this->{options}->{termoption}
			     },
			     $pOpt);
    my $checkpointMessage;
    if($check_syntax){
	my $test_preamble = "set terminal dumb\nset output \" \"\n";
	$PDL::Graphics::Gnuplot::last_testcmd = $test_preamble . $command;
	_printGnuplotPipe( $this, "syntax", $test_preamble . $command);
	$checkpointMessage = _checkpoint($this, "syntax");
	if($checkpointMessage) {
	    if($MS_io_braindamage) {
		print STDERR "WARNING: unexpected chatter while sending multiplot command:\n$checkpointMessage\n\n";
	    } else {
		barf("Gnuplot error: \"$checkpointMessage\" while sending multiplot command.");
	    }
	} 
    }
    
    $PDL::Graphics::Gnuplot::last_plotcmd = $preamble . $command;
    _printGnuplotPipe( $this, "main", $preamble . $command);
    $checkpointMessage = _checkpoint($this,"main");
    if($checkpointMessage){
	if($MS_io_braindamage) {
	    print STDERR "WARNING: unexpected chatter while sending final multiplot command:\n$checkpointMessage\n\n";
	} else {
	    barf("Gnuplot error: \"$checkpointMessage\" while sending final multiplot command.");
	}
    }
    
    $this->{options}->{multiplot} = 1;
    
    return;
}

sub end_multi {
    my $this = _obj_or_global(\@_);

    unless($this->{options}->{multiplot}) {
	barf("end_multi: you can't, you're not in multiplot mode\n");
    }
    my $checkpointMessage;
    if($check_syntax){
	_printGnuplotPipe( $this, "syntax", "unset multiplot\n");
	$checkpointMessage = _checkpoint($this, "syntax");
	if($checkpointMessage) {
	    barf("Gnuplot error: unset multiplot failed on syntax check!\n$checkpointMessage");
	}
    }
    
    _printGnuplotPipe($this, "main", "unset multiplot\n");
    $checkpointMessage = _checkpoint($this, "main");
    if($checkpointMessage) {
	if($MS_io_braindamage) {
	    print STDERR "WARNING: unexpected chatter after unset multiplot:\n$checkpointMessage\n";
	} else {
	    barf("Gnuplot error: unset multiplot failed!\n$checkpointMessage");
	}
    }

    $this->{options}->{multiplot} = 0;
}



######################################################################
##
## Input support
##

=head2 read_mouse - get a mouse click or keystroke from the active interactive plot window.

=for usage 

  ($x,$y,$char,$modstring) = $w->read_mouse($message);
  $hash = $w->read_mouse($message);

=for ref 

For interactive devices (e.g. x11, xwt, aqua), get_click lets you accept a 
keystroke or mouse button input from the gnuplot window.  In list context, it
returns four arguments containing the reported X, Y, keystroke character, and 
modifiers packed in a string.  In scalar context, it returns a hash ref containing
those things.

read_mouse blocks execution for input, but responds gracefully to interrupts.

=cut
my $mouse_serial = 0;
sub read_mouse {
    my $this = shift;
    my $message = shift // "Click mouse in plot to continue...";

    barf "read_mouse: This plot uses the '$this->{terminal}' terminal, which doesn't support mousing\n"
	unless($this->{mouse});

    barf "read_mouse: no existing plot to mouse on!\n"
	unless($this->{replottable});

    $mouse_serial++;
    my $string = _checkpoint($this, "main", {notimeout=>1});

    print STDERR $message;

    _printGnuplotPipe($this, "main", <<"EOC"
pause mouse any
if( exists("MOUSE_BUTTON") * exists("MOUSE_X") * exists("MOUSE_Y") )  print "Key: -1 at xy:",MOUSE_X,",",MOUSE_Y," button:",MOUSE_BUTTON," shift:",MOUSE_SHIFT," alt:",MOUSE_ALT," ctrl:",MOUSE_CTRL; else print "Key: ",MOUSE_KEY;
EOC
	);

    $string = _checkpoint($this, "main", {notimeout=>1});

    $string =~ m/Key: (\-?\d+)( +at xy:([^\s\,]+),([^\s\,]+)? button:(\d+)? shift:(\d+) alt:(\d+) ctrl:(\d+))?/ 
	|| barf "read_mouse: string $string doesn't look right - doesn't match parse regexp.\n";
    my($ch,$x,$y,$b,$sft,$alt,$ctl) = map { $_ // "" } ($1,$3,$4,$5,$6,$7,$8);

    if(wantarray) {
	return ($x,$y, ($ch>=32)?chr($ch):undef, 
		{
		    'b'=>$b,
		    'm'=>($sft?"S":"").($alt?"A":"").($ctl?"C":"")
		}
	    );
    } else {
	return {
	    'x' => $x,
	    'y' => $y,
            'b' => $b,
	    'k' => ($ch<0) ? "" : ($ch > 32 && $ch != 127) ? chr($ch) : sprintf("#%3.3d",$ch),
	    'm' => ($sft?"S":"").($alt?"A":"").($ctl?"C":"")
	};
    }
}

=head2 read_polygon

=for usage

  $points = $w->read_polygon(%opt)

=for ref

Read in a polygon by accepting mouse clicks.  The polygon is returned as a 2xN PDL of ($x,$y) values in scientific units. Acceptable options are:

=over 3

=item message - what to print before collecting points

There are some printf-style escapes for the prompt:
    

* C<%c> - expands to "an open" or "a closed" 

* C<%n> - number of points currently in the polygon

* C<%N> - number of points expected for the polygon

* C<%k> - list of all keys accepted

* C<%%> - %

=item prompt - what to print to prompt the user for the next point

 


=item n_points - number of points to accept (or 0 for indefinite)

With 0 value, points are accepted until the user presses 'q' or 'ESC' on the keyboard with focus
on the graph.  With other value, points are accepted until that happens *or* until the number
of points is at least n_points.

=item actions - hash of callback code refs indexed by character for action

You can optionally call a callback routine when any particular
character is pressed.  The actions table is a hash ref whose keys are
characters and whose values are either code refs (to be called on the
associated keypress) or array refs containing a short description
string followed by a code ref.  Non-printable characters (e.g. ESC,
BS, DEL) are accessed via a hash followed by a three digit decimal
ASCII code -- e.g. "#127" for DEL. Button events are indexed with the
strings "BUTTON1", "BUTTON2", and "BUTTON3", and modifications must be 
entered as well for shift, control, and 

The code ref receives the arguments ($obj, $c, $poly,$x,$y,$mods), where:

=over 2

=item C<$obj> is the plot object

=item C<$c> is the character (or "BUTTONC<n>" string),

=item C<$poly> is a scalar ref; $$poly is the current polygon before the action,

=item C<$x> and C<$y> are the current scientific coordinates, and

=item C<$mods> is the modifier string.

You can't override the 'q', or '#027' (ESC) callbacks.  You *can* override
the BUTTON1 and DEL callbacks, potentially preventing the user from entering points
at all!  You should do that with caution.

=item close - (default true): generate a closed polygon

=item markup - (default 'linespoints'): style to use to render the polygon on the fly

If this is set to a true value, it should be a valid 'with' specifier (curve option).  
The routine will call markup after each click.  

=back

=back

=cut

# This table describes option parsing for read_polygon.  Its format is the same as for the large
# $plotOptionsTable, below.  Full Gnuplot options parsing is perhaps a bit overblown for this 
# application, but it's present in the module so what the heck...

our $rpOptionsTable = {
    map { ( $_->[0] => ['ps',undef,undef,undef,$_->[1]] ) }
    ( ['message'  =>  "Message to print before reading in polygon"    ],
      ['prompt'   =>  "Message to print for each point",              ],
      ['n_points' =>  "Number of points (or 0 for indefinite)"        ],
      ['actions'  =>  "Hash ref containing callbacks for keystrokes"  ],
      ['close',   =>  "Flag: close polygon by copying first point"    ],
      ['markup'   =>  "Plot option for rendering, or undefined for none" ]
    ) };
our $rpOpt = [$rpOptionsTable, _gen_abbrev_list(keys %$rpOptionsTable), "read_polygon option"];

sub read_polygon {
    my $this = _obj_or_global(\@_);
    
    barf "read_polygon: $this->{terminal} terminal doesn't support mousing\n"
	unless($this->{mouse});

    my $u_opt = shift;

    my $poly = zeroes(2,0); # list of zero 2-D points
    local($this->{quit}) = 0;

    my $opt = {
	message  => <<'EOMSG'
Click points on the plot to form %c polygon.  Use keys in window:
%k
EOMSG
,
	prompt   => "(%n points in polygon) Waiting for plot input....",
        n_points => 0,
	close    => 1,
	markup   => "linespoints",
	actions=> {
	    # These defaults can be overridden.
	    'd'        => ['Delete last point (or DEL or backspace or shift-button)', \&__del],
	    '#010'     => \&__quit, # NEWLINE (ENTER)
	    '#013'     => \&__quit, # RETURN
	    "#127"     => \&__del,  # DEL
	    "#008"     => \&__del,  # BS
	    'BUTTON1S' => \&__del,  # shift-click
	    'BUTTON1'  => ['Add a point',\&__add],
	}
    };

    _parseOptHash( $opt, $rpOpt, @_ );

    my $a = $opt->{actions};
    $a->{"q"}    = ['Quit / finish entry (or ESC)', \&__quit ];
    $a->{"#027"} = \&__quit;

    ### Parsing is complete, actions are in place.

    my $pstring = sub {
	my $s = shift;
	my $z = ($opt->{close}) ? "a closed" : "an open";
	$s =~ s/\%c/$z/g;

	$z = $poly->dim(1);
	$s =~ s/\%n/$z/g;
	
	$z = $opt->{n_points} || "indefinite";
	$s =~ s/\%N/$z/g;

	if($s =~ m/\%k/) {
	    $z = "INPUT ACTIONS:\n";
	    for my $k(sort { (length($a) <=> length($b))  ||  ($a cmp $b) } keys %$a) {
		if(ref($a->{$k}) eq 'ARRAY') {
		    $z .= sprintf("%10s: %s\n",$k,$a->{$k}->[0]);
		}
	    }
	    $s =~ s/\%k/$z/g;
	}

	$s =~ s/\%\%/\%/g;
	return $s;
    };

    print &$pstring($opt->{message});
    
    my $h;
    do {
	$h = $this->read_mouse(&$pstring($opt->{prompt}));
	my $key = $h->{'b'} ? "BUTTON".$h->{'b'}.$h->{'m'} : $h->{'k'};

	if(ref $a->{$key}) {
	    my $z = (ref($a->{$key}) eq 'CODE') ? $a->{$key} : $a->{$key}->[1];
	    &$z($this, $key, \$poly, $h->{x}, $h->{y}, $h->{'m'});
	} else {
	    print "$key! ";
	}
	print "\n";

	if($opt->{markup}){
	    $this->markup( with => $opt->{markup},$poly->mv(-1,0)->dog);
	}

    } while(($h->{'b'} || $h->{'k'}) and !$this->{quit} and ($opt->{n_points}==0  or $poly->dim(1)<$opt->{n_points}));
    
    print "\n";
    
    if($opt->{'close'}) {
	$poly = $poly->glue(1,$poly->slice(":,(0)"));
	if($opt->{markup}) {
	    $this->markup( with => $opt->{markup},$poly->mv(-1,0)->dog);
	}
    }

    return $poly;

use PDL::NiceSlice;
    sub __del { my($w, $c, $p) = @_;
	   return unless( (ref($$p) eq 'PDL')  and  ($$p->dim(1)>0) );
	   $$p = $$p->(:,xvals($$p->dim(1)-1))->sever;
	   return;
    }

    sub __quit { $_[0]->{quit} = 1; }
    
    sub __add { my($w,$c,$p,$x,$y,$m) = @_;
		$$p = $$p->glue(1,pdl($x,$y));
    }

no PDL::NiceSlice;
		    
}

######################################################################
######################################################################
######################################################################
##### 
##### Parsing routines
#####
##### The task of parsing input parameters is nontrivial.  It is 
##### pushed off to several internal routines:
#####

######################################################################
# parsing helpers...

sub _gen_abbrev_list {
    my @keys = @_;
    my $hash = {};
    for my $k(@keys) {
	for my $i(0..length($k)-2) {
	    my $s = substr($k,0,$i+1);
	    if(exists($hash->{$s})) {
		push(@{$hash->{$s}},$k) 
		    unless($hash->{$s}->[0] eq $s);  # exact matches override abbrevs
	    } else {
		$hash->{$s} = [$k];
	    }
	}
	$hash->{$k}=[$k];  # exact match always matches only the exact match
    }
    return $hash;
}

sub _expand_abbrev {
    my $s = shift;
    my $sl = lc($s);
    my $abbrevs = shift;
    my $name = shift;

    my $snum = undef;
    if($sl =~ s/(\d+)\s*$//) {
	$snum = $1;
    }

    if(exists($abbrevs->{$sl})) {
	if(@{$abbrevs->{$sl}}>1) {
	    barf "Error: ambiguous $name: '$s' could be one of { ".join(", ",@{$abbrevs->{$sl}})." }\n";
	} else {
	    if(wantarray) {
		return ($abbrevs->{$sl}->[0],$snum);
	    } else {
		return $abbrevs->{$sl}->[0];
	    }
	}
    } else {
	die "No $name found that matches '$s'\n";
    }
    barf "This can't happen";
}
	
##########
# pOptionsTable - describes valid plot options and their allowed value types
#
# The keywords are the option name (from the Gnuplot 4.4 manual); the values are 
# a list ref containing:
#   - value type:
#     * list ref for a single value with options (first is default)
#     * "b" for boolean flag (actually ternary: true/false/undef)
#     * "n" for number
#     * "s" for a scalar string 
#     * "l" for a list of options; none required; passing in a number yields a boolean, or undef deletes. 
#     * "C" for cumulative list of options; scalar values OK
#     * "H" for a hash list of options 
#     * "N" for multivalue with optional first-parameter index
#            (NOTE this is explicitly hardwired into _parseOptHash to accept trailing numbers
#             in the keyword itself, to enable passing multiple multivalue numbers with different labels
#             in a hash ref -- search for "HARDWIRED-N" to find the place)
#     * code ref for code checker: gets ($old-val, $new-param, $hash); returns new values 
#               (with possible side effects on the object, e.g. for "device")
#   - output form:
#     * nothing: output single value or all list values on a single line
#     * ",":     output list values as a comma-separated list on a single line (default is with spaces)
#     * "1":     output list values one per line
#     * "H":     output hash-of-lists, one list per line, with leading key
#     * "N":     output list-of-lists, one list per line, with leading index  
#     * code ref for code emitter: accepts key, value, source options hash, and object; returns 
#                                  (potentially multiline) string of commands.
#     * hash ref for value context switch: keys are
#        accepted/understood keywords, values are output form for further keywords.  
#        This is only valid with options lists ('l' input), and is used to keep track of 
#        (e.g.) which keywords should be auto-quoted.
#
#   - sort-after:
#     * nothing: can appear in no particular order
#     * list ref: options later than which this option should be presented
#
#   - sort-order
#     * a number: numbered options, if present appear at the beginning of the option dump, in numerical order.
#   - documentation-string (optional)
#
# keywords with capital-letter value types are recognized even with a trailing number in the keyword;
# this is to allow multiple values to be set in a single hash.  In the default scalar output, the
# empty string causes "unset" to be emitted, while undef causes nothing to be emitted.
our $palettesTab;

# suffix => terminal type
our $hardCopySuffixes = {
    'gif'=>'gif',
    'jpg'=>'jpeg',
    'jpeg'=>'jpeg',
    'pdf'=>'pdfcairo',
    'png'=>'png',
    'ps'=>'postscript',
    'eps'=>'postscript eps',
    'svg'=>'svg'
};
    
    
our $pOptionsTable = 
{
    # Start with pseudo-options we use internally.
    '3d'        => ['s', sub { "" }, undef, undef, 
		    '[pseudo] Make the current plot 3d (gnuplot "splot" command).'
    ],
    'trid'      => [sub { my($o,$n,$h)=@_; $h->{'3d'}=$n; return undef}, sub { "" }, undef, undef,
		    '[pseudo] Make the current plot 3d (synonym for "3d").'
		    ],
    'binary'    => ['b', sub {""}, undef, undef, 
                    '[pseudo] Communicate with gnuplot in binary mode (default).'
    ],
    'device'     => [ sub { my ($old, $new, $hash) = @_; 
			    barf "Can't set device while in multiplot mode!\n" if($hash->{multiplot});
			    if( $new =~ m/^(.*)\/([^\/]*)$/ ) {
				$hash->{terminal} = $2;
				$hash->{output}   = $1 || undef;
			    } else {
				barf("Device option format: [<filename>]/<terminal-type>\n");
			    }
			    return undef;
		      }, 
		      sub { "" }, undef, undef,
		      '[pseudo] Shorthand for device spec.: "dev=>\'<output/<terminal>\'".'
    ],
    
    'hardcopy'  => [ sub { my ($old, $new, $hash) = @_;
			   barf "Can't set hardcopy while in multiplot mode!\n" if($hash->{multiplot});
			   if( $new =~ m/^\.([a-z]+)$/) {
			       my $suffix = lc $1;
			       if($hardCopySuffixes->{$suffix}) {
				   $hash->{terminal} = $hardCopySuffixes->{$suffix};
				   $hash->{output} = $new;
				   return undef;
			       } else {
				   die "hardcopy: couldn't identify file type from '$new'\n";
			       } 
			   } else {
			       die "hardcopy: need a file suffix to infer file type\n";
			   }
		     }, sub {""},undef,undef,
		     '[pseudo] Shorthand for device spec.: standard image formats inferred by suffix'
    ],

    'dump'      => [
	sub { my $newval = ( (defined $_[1]) ? ($_[1] ? 1 : 0) : undef); # same as boolean code
	      if($newval && !$_[2]->{dump}) {
		  print STDERR "WARNING - dumping ON - gnuplot commands go to the terminal only.\n";
	      } elsif($_[2]->{dump} && !$newval) {
		  print STDERR "WARNING - dumping OFF - gnuplot commands will be used for plotting.\n";
	      }
	      return $newval;
	},
	                 sub { "" },undef, undef,
	            '[pseudo] Redirect gnuplot commands to stdout for inspection'
    ],

    'tee'       => ['b', sub { "" }, undef, undef,
		    '[pseudo] Tee gnuplot commands to stdout for inspection'
    ],

    'silent'      => ['b', sub { "" }, undef, undef, 
		    '[pseudo] Be silent about gnuplot errors'
    ],

      # topcmds/extracmds/bottomcmds: contain explicit strings for gnuplot.
      # topcmds go just below the "set term", "set termoption", and "set output" commands;
      # extracmds go after all the auto-generated commands and just before the plot lines
      # bottomcmds comes after everything -- useful for cleanup after the plot command 
      #is sent.
    'topcmds'   => ['l', sub { my($k,$v,$h) = @_;
			       return (ref $v eq 'ARRAY') ? join("\n",(@$v,"")) : $v."\n"; },
		    undef, 10,
		    '[pseudo] extra gnuplot commands at the top of the command block'
    ],

    'extracmds' => ['l', sub { my($k,$v,$h) = @_;
			       return (ref $v eq 'ARRAY') ? join("\n",(@$v,"")) : $v."\n"; },
		       ,undef, 1001,
		    '[pseudo] extra gnuplot commands between plot options and the plots'
    ],
			# bottomcmds is implemented by special hook in plot().
    'bottomcmds' => ['l', sub {""}, undef, undef,
		     '[pseudo] extra gnuplot commands after all plot commands'
    ],

    'globalwith'=> ['l', sub { "" }, undef, undef,
		    '[pseudo] default plot style (overridden by "with" in curve options)'
    ],

 
   'clut'      => [sub { my($old, $new, $this) = @_;
			  $new = ($new ? lc $new : "default");
			  if($palettesTab->{$new}) {
			      return $new;
			  } else {
			      my $s = "Unknown lookup table name passed as a 'clut' option.  Acceptable values are:\n";
			      for my $k(sort 
					{$a eq 'default' ? $b : $a eq 'default' ? $b : $a cmp $b} 
					keys %$palettesTab 
				  ) {
				  $s .= sprintf("   %10.10s (%s)\n",$k, $palettesTab->{$k}->[2]);
			      }
			      barf($s);
			  }
		    },
		    sub { my($k, $v, $h) = @_;
			  my $s = "";
			  unless($palettesTab->{$v}) { die "Color table lookup failed -- this should never happen" }
			  if(defined($palettesTab->{$v}->[0])) {
			      $s .= "set palette model $palettesTab->{$v}->[0]\n";
			  }
			  $s .= "set palette $palettesTab->{$v}->[1]\n";
			  $s;
		    },
		    ['palette'],undef,
		    '[pseudo] Use named color look-up table for palette: "clut=>\'heat2\'"'
    ],

    'globalwith'=> ['l',sub { return '' },undef,undef,
		    '[pseudo] Set default "with" plot style for the object'
    ], # pseudo-option to add 'with' parameters

    'globalPlot'=> ['l',sub { return '' },undef,undef,
		    '[pseudo] marker for the global plot object'
    ], 

    'justify'   => [sub { my($old,$new,$opt) = @_;
			  if($new > 0) {
			      $opt->{'size'} = ["ratio ".(-$new)];
#			      if($new==1){
#				  $opt->{'view'} = [] unless defined($opt->{'view'});
#				  @{$opt->{'view'}}[2..5] = ($new,$new,"equal","xyz");
#			      }
			      return undef;
			  } else {
			      die "justify: positive value needed\n";
			  }
		    }, 
		    sub { '' }, undef, undef,
		    '[pseudo] Set aspect ratio (equivalent to: size=>["ratio",<r>])'
    ],
    'square'    => [sub { my($old, $new, $opt) = @_;
			  if($new) {
			      $opt->{'size'} = ["ratio -1"];
			      $opt->{'view'} = [] unless defined($opt->{'view'});
			      @{$opt->{'view'}}[2..5] = ($new, $new, "equal", "xyz");
			      return undef;
                          } else {
			      delete($opt->{'size'}) if(exists($opt->{'size'}));
			      delete $opt->{'view'} if(exists($opt->{'view'}));
			  }
		    },
                    sub { return '' }, undef, undef,
		    '[pseudo] Set aspect ratio to square (equivalent to: size=["ratio",1])'
    ],
    ##############################		    
    # These are all the "plot" (top-level) options recognized by gnuplot 4.4.
    'angles'    => ['s','s',undef,undef,
		    '(radians or degrees): sets unit in which angles will be specified'
    ],
    'arrow'     => ['N','N',undef,undef,
		    'allows specification of arrows to be drawn on subsequent plots'
    ],
    'autoscale' => ['l','1',undef,undef,
		    'autoscaling style: autoscale=>"(x|y|z|cb|x2|y2|xy) (fix)?(min|max)?".'
    ],
    'bars'      => ['l','l',undef,undef,
		    'errorbar ticsize: bars=>"(small|large|fullwidth|<size>) (front|back)?"'
    ],
    'bmargin'   => ['s','s',undef,undef,
		    'bottom margin (chars); bmargin=>"at screen <frac>" for pane-rel. size'
    ],
    'border'    => ['l','l',undef,undef,
		    'specify border around the plot (see gnuplot manual)'
    ],
    'boxwidth'  => ['l','l',undef,undef,
		    'default width of boxes in those plot styles that have them'
    ],
    'cbdata'    => ['s','bt',    ['colorbox'], undef,
		    'cbdata=>"time" to use time stamps on color box data axis (see timefmt)'
    ],
    'cbdtics'   => ['b','b',    ['colorbox'], undef,
		    'cbdtics=>1 to use days-of-week tick labels on the color box axis'
    ],
    'cblabel'   => ['l','ql',  ['colorbox'], undef,
		    'sets the label on the color box axis'
    ],
    'cbmtics'   => ['b','b',    ['colorbox'], undef,
		    'cbmtics=>1 to use months-of-year tick labels on the color box axis'
    ],
    'cbmin'      => [sub { my($o,$n,$h)=@_; $h->{cbrange}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of cbrange'
    ],
    'cbmax'      => [sub { my($o,$n,$h)=@_; $h->{cbrange}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of cbrange'
    ],

    'cbrange'   => ['l','range',['colorbox'], undef,
		    'controls rendered range of color data values: cbrange=>[<min>,<max>]'
    ],
    'cbmin'      => [sub { my($o,$n,$h)=@_; $h->{cbrange}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of cbrange'
    ],
    'cbmax'      => [sub { my($o,$n,$h)=@_; $h->{cbrange}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of cbrange'
    ],
    'cbtics'    => ['lt','l',  ['colorbox'], undef,
		    'controls major (labelled) ticks on the color box axis (see docs)'
    ],
    'clabel'    => ['s','q',undef,undef,
		    'Contour level legend format for contour plots (default "%8.3g")'
    ],
    'clip'      => ['H','H',undef,undef,
		    'control filtering near boundary: clip=>{points=>1,one=>0,two=>1}'
    ],
    'cntrparam' => ['l','1',undef,undef,
		    'control contour plotting parameters (see docs)'
    ],
    'colorbox'  => ['l','l',undef,undef,
		    'set color box options for pm3d and image; set to undef to remove box'
    ],
    'contour'   => ['s','s',undef,undef,
		    'control 3d contour plots: contour=>("base"|"surface"|"both"|undef)'
    ],
    'datafile'  => ['H','H',undef,undef,
		    'control how gnuplot interprets data files (not recommended)'
    ],
    'decimalsign'=>['s','q',undef,undef,
		    'control character used for decimal point in labels'
    ],
    'dgrid3d'   => ['l','l',undef, undef,
		    'set up interpolation of scattered datapoints onto a regular grid'
    ],
    'dummy'     => ['l',',', undef, undef,
		    'change name of dummy variable for parametric plots (not recommended)'
    ],
    'encoding'  => ['s','s', undef, undef,
		    'change locale of character encoding (not recommended)'
    ],
    'fit'       => [sub { die "set fit: not (yet) implemented in PDL Gnuplot interface\n";}],
    'fontpath'  => ['l','l',undef,undef,
		    'set directories to search when looking for fonts (PostScript only)'
    ],
    'format'    => ['H','H',undef,undef,
		    'Fine-grained control over formatting of axis labels'
    ],
    'function'  => [sub { die "'set function' is deprecated by gnuplot and not allowed here\n"; }
    ],
    'grid'      => ['l','l',undef,undef,
		    'draw grid lines on the plot (see docs)'
    ],
    'hidden3d'  => ['l','l',undef,undef,
		    'control whether and how hidden lines are removed in 3d (see docs)'
    ],
    'isosamples'=> ['l','l',undef,undef,
		    'control isoline density for plotting functions as surfaces'
    ],
    'key'       => ['l','l',undef,undef,
		    'enable key/legend and control its position and appearance (see docs)'
    ],
    'label'     => ['N','NL',undef,undef,
		    'Define text labels to be rendered in plot (numeric index; see docs)'
    ],
    'lmargin'   => ['s','s',undef,undef,
		    'left margin (chars); lmargin=>"at screen <frac>" for pane-rel. size'
    ],
    'loadpath'  => [sub { die "loadpath not supported\n"; }],
    'locale'    => ['s','q',undef,undef,
		    'set named locale for date/month formatting'
    ],
    'logscale'  => ['l','l',undef,undef,
		    'set log scaling and base: e.g. logscale=>["xyx2cb",10]'
    ],
    'macros'    => [sub { die "macros: not supported\n"; } ],
    'mapping'   => ['s','s',undef,undef,
		    'set coordinates for 3d plots: "cartesian","spherical", or "cylindrical"'
    ],
    # multiplot: this is not emitted as part of any plot command, only by the special multiplot method.
    'multiplot' => [sub { die "multiplot: use the 'multiplot' method, don't set this directly\n" },sub { ""},undef,undef,undef]
    ,
    'mxtics'    => ['l','l',undef,undef,
		    'set and control minor ticks on the X axis: mxtics=><freq>'
    ],
    'mx2tics'   => ['l','l',undef,undef,
		    'set and control minor ticks on the X2 axis: mx2tics=><freq>'
    ],
    'mytics'    => ['l','l',undef,undef,
		    'set and control minor ticks on the Y axis: mytics=><freq>'
    ],
    'my2tics'   => ['l','l',undef,undef,
		    'set and control minor ticks on the Y2 axis: my2tics=><freq>'
    ],
    'mztics'    => ['l','l',undef,undef,
		    'set and control minor ticks on the Z axis: mztics=><freq>'
    ],
    'object'    => ['N','NO',undef,undef,
		    'define objects to be overlain on plot (numeric index; see docs)'
    ],
    'offsets'   => ['l','l',undef,undef,
		    'define inside-axis blank margin (science units): [<l>,<r>,<t>,<b>]'
    ],
    'origin'    => ['l',',',undef,undef,
		    'set 2-D origin of the plotting surface in relative screen coordinates'
    ],
    'output'    => [sub { my($k,$v,$h) = @_;
			  unless(defined($h) and $h->{globalPlot}) {barf("Don't set output as a plot option; use the constructor\n");}
			  return $v;
		    },
		    'qnm',undef,3,
		    'set output file or label for plot (see "terminal", "device")'
    ],
    'parametric'=> ['b','b',undef,undef,
		    'sets parametric mode for plotting parametric curves (boolean)'
    ],
    'pm3d'      => ['l','l',undef,undef,
		    'sets up color palette-mapped 3d surface plots (see docs)'
    ],
    'palette'   => ['l','l',undef,undef,
		    'sets up color palette for color mapped plots (see docs and "clut")'
    ],
    'pointsize' => ['s','s',undef,undef,
		    'sets the size of plotted point symbols (multiplier on base size)'
    ],
    'polar'     => ['b','b',['angles'],undef,
		    'sets 2-D plots into polar coordinates.  (see also "angles")'
    ],
    'rmargin'   => ['s','s',undef,undef,
		    'right margin (chars); rmargin=>"at screen <frac>" for pane-rel. size'
    ],
    'rrange'    => ['l','range',undef,undef,
		    'radial coordinate range in polar mode: rrange=>[<lo>,<hi>]'
    ],
    'size'      => ['l','l',['view'],undef,
		    'sets the size of the plot pane relative to the main window (see also "justify")'
    ],
    'style'     => ['H','H',undef,undef,
		    'Set various aspects of plot style by keyword (see docs)'
    ],
    'surface'   => ['b','b',undef,undef,
		    'Turn on/off surface drawing in 3-d plots (boolean)'
    ],
    'table'     => [sub { die "table not supported - use Perl's 'print' instead\n" }
    ],
    'terminal'  => [sub { my($k,$v,$h)=@_;
			  unless(defined($h) and $h->{globalPlot}) {barf("Don't set terminal as a plot option; use the constructor\n")}
			  return $v;
		    },
		    'nomulti',
		    undef,1,
		    'Set the output device type and device dependent options (see docs)\n'
    ],
    'termoption'=> ['H','HNM',undef,2,
		    'Set certain options for the terminal driver, by keyword'
    ],
    'tics'      => ['l','l',undef,undef,
		    'Control tick mark formatting (<axis>tics recommended instead)'
    ],
    'timestamp' => ['l','l',undef,undef,
		    'creates a timestamp in the left margin of hte plot (see docs)'
    ],
    'timefmt'   => [sub { print STDERR "Warning: timefmt doesn't work well in formats other than '%s'.  Proceed with caution!\n"
			      if(  defined($_[1])   and    $_[1] ne '%s');
			  return ( (defined $_[1]) ? "$_[1]" : undef );
		    },'s',undef,undef,
		    'Sets format for interpreting time data (leave as "%s"; see docs)'
    ],
    'title'     => ['l','ql',undef,undef,
		    'Set title for the plot.  See docs for size/color/font options'
    ],
    'tmargin'   => ['s','s',undef,undef,
		    'top margin (chars); tmargin=>"at screen <frac>" for pane-rel. size' 
    ],
    'trange'    => ['l','range',undef,undef,
		    'range for indep. variable in parametric plots: trange=>[<min>,<max>]'
    ],
    'urange'    => ['l','range',undef,undef,
		    'range for indep. variable "u" in 3-d parametric plots: [<min>,<max>]'
    ],
    'view'      => ['l', sub { my($k,$v,$h)=@_;
			       return "" unless defined($v);
			       return "set view 60,30,1.0,1.0\nset view noequal\n" unless( ref $v eq 'ARRAY' ); # default value from manual
			       my @numbers = ();
			       my @v = @$v;
			       
			       while( @v && (($v[0]//"") =~ m/^(\s*\-?((\d+\.?\d*)|(\d*\.\d+))([eE][\+\-]\d*)?\s*)?$/ )) {
				   push(@numbers, (shift(@v)//""));
			       }
			       my $s = "";
			       $s .= "set view ".join(",",@numbers)."\n" if(@numbers);
			       while(@v) {
				   if($v[0] eq 'equal' and $v[1] =~ m/xyz?/) {
				       $s .= sprintf("set view %s %s\n",splice(@v,0,2));
				   } else {
				       $s .= sprintf("set view %s\n",shift @v);
				   }
			       }
			       return $s;
		    },
		    undef,undef,
		    '3-d view: [r_x, r_z, scale, sc_z,"map","noequal","equal (xy|xyz)"]'
    ],
    'vrange'    => ['l','range',undef,undef,
		    'range for indep. variable "v" in 3-d parametric plots: [<min>,<max>]'
    ],
    'x2data'    => ['s','bt',undef,undef,
		    'x2data=>"time" to use time stamps on X2 axis (see timefmt)'
    ],
    'x2dtics'   => ['b','b',undef,undef,
		    'x2dtics=>1 to use days-of-week tick labels on X2 axis'
    ],
    'x2label'   => ['l','ql',undef,undef,
		    'sets label for the X2 axis.  See docs for size/color/font options'
    ],
    'x2mtics'   => ['b','b',undef,undef,
		    'x2mtics=>1 to use months-of-year tick labels on the X2 axis'
    ],
    'x2min'      => [sub { my($o,$n,$h)=@_; $h->{x2range}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of x2range'
    ],
    'x2max'      => [sub { my($o,$n,$h)=@_; $h->{x2range}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of x2range'
    ],
    'x2range'   => ['l','range',undef,undef,
		    'set range of X2 axis: x2range=>[<min>,<max>]'
    ],
    'x2tics'    => ['lt','l',undef,undef,
		    'Control tick mark formatting (X2 axis; see docs)'
    ],
    'x2zeroaxis'=> ['l','l',undef,undef,
		    'If set, draw a vertical line at X2=0; see docs for formatting'
    ],
    'xdata'     => ['s','bt',undef,undef,
		    'xdata=>"time" to use time stamps on X axis (see timefmt)'
    ],
    'xdtics'    => ['b','b',undef,undef,
		    'xdtics=>1 to use days-of-week tick labels on X axis'
    ],
    'xlabel'    => ['l','ql',undef,undef,
		    'sets label for the X axis.  See docs for size/color/font options'
    ],
    'xmtics'    => ['b','b',undef,undef,
		    'xmtics=>1 to use months-of-year tick labels on the X axis'
    ],
    'xmin'      => [sub { my($o,$n,$h)=@_; $h->{xrange}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of xrange'
    ],
    'xmax'      => [sub { my($o,$n,$h)=@_; $h->{xrange}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of xrange'
    ],
    'xrange'    => ['l','range',undef,undef,
		    'set range of X axis: xrange=>[<min>,<max>]'
    ],
    'xtics'     => ['lt','l',undef,undef,
		    'Control tick mark formatting (X axis; see docs)'
    ],
    'xyplane'   => ['l','l',undef,undef,
		    'Sets location of the XY plane in 3-D plots; see docs'
    ],
    'xzeroaxis' => ['l','l',undef,undef,
		    'if set, draw a vertical line at X=0; see docs for formatting'
    ],
    'y2data'    => ['s','bt',undef,undef,
		    'y2data=>"time" to use time stamps on Y2 axis (see timefmt)'
    ],
    'y2dtics'   => ['b','b',undef,undef,
		    'y2dtics=>1 to use days-of-week tick labels on Y2 axis'
    ],
    'y2label'   => ['l','ql',undef,undef,
		   'sets label for the Y2 axis.  See docs for size/color/font options'
    ],
    'y2mtics'   => ['b','b',undef,undef,
		    'y2mtics=>1 to use months-of-year tick labels on Y2 axis'
    ],
    'y2min'      => [sub { my($o,$n,$h)=@_; $h->{y2range}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of y2range'
    ],
    'y2max'      => [sub { my($o,$n,$h)=@_; $h->{y2range}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of y2range'
    ],
    'y2range'   => ['l','range',undef,undef,
		    'set range of Y2 axis: y2range=>[<min>,<max>]'
    ],
    'y2tics'    => ['lt','l',undef,undef,
		    'Control tick mark formatting (Y2 axis; see docs)'
    ],
    'y2zeroaxis'=> ['l','l',undef,undef,
		    'if set, draw a horizontal line at Y2=0; see docs for formatting'
    ],
    'ydata'     => ['s','bt',undef,undef,
		    'ydata=>"time" to use time stamps on Y axis (see timefmt)'
    ],
    'ydtics'    => ['b','b',undef,undef,
		    'ydtics=>1 to use days-of-week tick labels on Y axis'
    ],
    'ytics'     => ['lt','l',undef,undef,
		    'Control tick mark formatting (Y axis; see docs)'
    ],
    'ylabel'    => ['l','ql',undef,undef,
		    'sets label for the Y axis.  See docs for size/color/font options'
    ],
    'ymtics'    => ['b','b',undef,undef,
		    'ymticks=>1 to use months-of-year tick labels on Y axis'
    ],
    'ymin'      => [sub { my($o,$n,$h)=@_; $h->{yrange}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of yrange'
    ],
    'ymax'      => [sub { my($o,$n,$h)=@_; $h->{yrange}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of yrange'
    ],
    'yrange'    => ['l','range',undef,undef,
		    'set range of Y axis: yrange=>[<min>,<max>]'
    ],
    'yzeroaxis' => ['l','l',undef,undef,
		    'if set, draw a horizontal line at Y=0; see docs for formatting'
    ],
    'zdata'     => ['s','bt',undef,undef,
		    'zdata=>"time" to use time stamps on Z axis (see timefmt)'
    ],
    'zdtics'    => ['b','b',undef,undef,
		    'zdtics=>1 to use days-of-week tick labels on Z axis'
    ],
    'zlabel'    => ['l','ql',undef,undef,
		    'sets label for the Z axis.  See docs for size/color/font options'
    ],
    'zmtics'    => ['b','b',undef,undef,
		    'zmtics=>1 to use months-of-year tick labels on Z axis'
    ],
    'zmin'      => [sub { my($o,$n,$h)=@_; $h->{zrange}->[0]=$n; return undef},sub{''},undef,undef,
		    'sets minimum end of zrange'
    ],
    'zmax'      => [sub { my($o,$n,$h)=@_; $h->{zrange}->[1]=$n; return undef},sub{''},undef,undef,
		    'sets maximum end of zrange'
    ],
    'zrange'    => ['l','range',undef,undef,
		    'set range of Z axis: zrange=>[<min>,<max>]'
    ],
    'zzeroaxis' => ['l','l',undef,undef,
		    'if set, draw a line through (X=0,Y=0) on a 3-D plot.  See docs'
    ],
    'zero'      => ['s','s',undef,undef,
		    'Sets the default threshold for values approaching 0.0'
    ],
    'ztics'     => ['lt','l',undef,undef,
		    'Control tick mark formatting (Z axis; see docs)'
    ]

};
our $pOptionsAbbrevs = _gen_abbrev_list(keys %$pOptionsTable);
$pOptionsAbbrevs->{'term'} = ['terminal'];         # frequently-used case
$pOptionsAbbrevs->{'time'} = ['timestamp'];        # compat. with gnuplot's alt. spelling

$pOpt = [$pOptionsTable, $pOptionsAbbrevs, "plot option"];


##########
# cOptionsTable - describes valid curve options and their allowed value types
#
# This works similarly to the pOptionsTable, above.
# 
# The output types are different so that they can all be interpolated into the same
# master table.  Curve option output routines have a 'c' in front of the name.  
#

our $cOptionsTable = {
    'trange'   => ['l','crange',undef,1],  # parametric range modifier
    'xrange'   => ['l','crange',undef,2],  # x range modifier
    'yrange'   => ['l','crange',undef,3],  # y range modifier
    'zrange'   => ['l','crange',undef,4],  # z range modifier
         # data is here so that it gets sorted properly into each chunk -- but it doesn't get specified this way.
         # the output string just specifies STDIN.   The magic output string gets replaced post facto with the test and
         # real output format specifiers.
    'cdims'     => [sub { my $s = $_[1] // 0;  # Number of dimensions in a column
			  if($s==0 or $s==1 or $s==2) {
			      return $s;
			  } else {
			      barf "Curve option 'cdims' must be one of 0, 1, or 2\n";
			  }
		    },			  
		    sub { return ""}],
    'data'     => [sub { barf "mustn't specify data as a curve option...\n" },
		   sub { return " $cmdFence "; },
		   undef,5
		   ],
    'using'    => ['l','cl',undef,6],        # using clauses in order (straight passthrough)
# legend is a special case -- it gets parsed as a list but emitted as a quoted scalar.
    'legend'   => ['l', sub { if(defined($_[1]) and $_[1]->[0]) {return "title \"$_[1]->[0]\"";} else {return "notitle"}},
		   undef, 7],
    'axes'     => [['(x[12])(y[12])'],'cs',undef,8],
    'smooth'   => ['s','cs',undef,8.1],
    'with'     => ['l', 'cl', undef, 9],
    'tuplesize'=> ['s',sub { return ""}]    # holds tuplesize option for explicit setting
};

our $cOptionsAbbrevs = _gen_abbrev_list(keys %$cOptionsTable);
$cOpt = [$cOptionsTable, $cOptionsAbbrevs, "curve option"];





##########
# $plotStyleProps
#
# This table describes the types of input expected by the various 
# plot styles.  Each entry should be an array ref.  The colums are:
#
#   0:  "ts"   Tuple sizes (columns of data) that are allowed by this plot style for
#              ordinary 2-D plots.  (We let gnuplot interpret the columns; this just 
#              keeps track of the different numbers of columns that are allowed).  If 
#              a plot style isn't allowed in 2-D, then this entry should be a false value.
#              Negative values get the "array" rather than the "record" specifier (for autogen
#              of coordinates)
#
#   1:  "3dts" Tuple sizes (columns of data) that are allowed by this plot style for 
#              3-D plots (with the gnuplot "plots" command).  If this plot style doesn't
#              work in 3-D, then the entry should be a false value instead.
#
#   2:  img    This is a flag indicating whether it is an image format plot (which accepts
#              2-D matrix data in each "column").  If false, the column is a 1-D collection
#              of values.
# 
#   3:  bin    0/1/undef - 0: ASCII data required for this plot type; 1: binary data required.
#
#   4:  frob   if present, pointer to a prefrobnication routine to prepare the data.
#              Currently, fits images are handled that way because of gnuplot's problem
#              dealing with proper coordinate grids -- the fits image is sampled into 
#              scientific coordinates using PDL::Transform.  The prefrobnicator should accept:
#               * the 'with' option list ref, 
#               * the main plot object (for access to plot options) 
#               * the plot chunk (for access to curve options), 
#               * all the data passed in for that curve.
#              It should return the new data piddle list, and modify the chunk 'with' list and curve options in place.
#              While it has access to plot options, it probably shouldn't modify them.

our $plotStyleProps ={
### key                ts         3dts         img  bin     prefrobnicator 
    boxerrorbars   => [ [3,4,5],  0,            0, undef ],
    boxes          => [ [2,3],    0,            0, undef ],
    boxxyerrorbars => [ [4,6],    0,            0, undef ],
    candlesticks   => [ [5,6],    0,            0, undef ],
    circles        => [ [2,3],    0,            0, undef ],
    dots           => [ [-1,2],   [3],          0, undef ],
    ellipses       => [ [2,3,4,5],0,            0, undef ],
    filledcurves   => [ [2,3],    0,            0, undef ],
    financebars    => [ [5],      0,            0, undef ],
    fsteps         => [ [-1,2],   0,            0, undef ],
    histeps        => [ [-1,2],   0,            0, undef ],
    histogram      => [ [1..99],  0,            0, undef ],
    newhistogram   => [ [1..99],  0,            0, undef ],
    fits           => [ [-1],     [-1],         1, 1     , \&_with_fits_prefrobnicator ],
    image          => [ [-1,3],   [-1,4],       1, 1     ],
    impulses       => [ [-1,2,3], [-1,-2,3,4],  0, undef ],
    labels         => [ [3],      [4],          0, 0     ], 
    lines          => [ [-1,2],   [-1,3],       0, undef ],
    linespoints    => [ [-1,2],   [-1,3],       0, undef ],
    points         => [ [-1,2],   [-1,3],       0, undef ],
    rgbalpha       => [ [-4,6],   [-4,7],       1, 1     ],
    rgbimage       => [ [-3,5],   [-3,6],       1, 1     ],
    steps          => [ [-1,2],   0,            0, undef ],
    vectors        => [ [4],      [6],          0, undef ],
    xerrorbars     => [ [-2,3,4], 0,            0, undef ],
    xyerrorbars    => [ [-3,4,6], 0,            0, undef ],
    yerrorbars     => [ [-2,3,4], 0,            0, undef ],
    xerrorlines    => [ [-3,4],   0,            0, undef ],
    xyerrorlines   => [ [-4,6],   0,            0, undef ],
    yerrorlines    => [ [-3,4],   0,            0, undef ],
    pm3d           => [ 0,        [-1,3,4],     1, 1 ]
};

##############################
# plotStyleDocs - just a one-line string for summarizing each plot style.  
# These are not (yet) used but should be incorporated into a documentation schema.
our $plotStyleSyntax = 'Tuple columns are listed for each style. "[]": optional.  "{}": 3-D style';
our $plotStyleDocs ={
    boxerrorbars   => ["boxes on X axis",                       "x, y, dy, [dx]; x, y, ylo, yhi, dx"],
    boxes          => ["boxes sitting on X axis",               "x, y, [dx]"],
    boxxyerrorbars => ["XY errorbars as rectangles",            "x, y, dx, dy; x, y, xlo, xhi, ylo, yhi"],
    candlesticks   => ["box-and-errorbar plots",                "x, blo, wlo, whi, bhi,"],
    circles        => ["circles",                               "x, y, [r]"],
    dots           => ["Tiny dots (scatterplot)",               "[x], y; {x, y, z}"],
    ellipses       => ["ellipses",                              "x, y, [dmaj, [dmin, [ang]]]"],
    filledcurves   => ["fill polygon, to axis, or topoint",     "x, y; x, y1, y2"],
    financebars    => ["financial stem plot",                   "x, open, lo, hi, close"],
    fsteps         => ["steps (Y first; cf histeps, steps)",    "[x], y"],
    histeps        => ["steps (centered; cf fsteps, steps)",    "[x], y"],
    histograms     => ["histogram (set tuplesize if >99 cols)", "y, [y1, [y2, [...]]]"],
    newhistogram   => ["histogram (set tuplesize if >99 cols)", "y, [y1, [y2, [...]]]"],
    fits           => ["FITS image with WCS info in header",    "[x, y], i; {[x, y, z], i}"],
    image          => ["I (WxH), RGB (WxHx3) or RGBA (WxHx4)",  "[x, y], i; {[x, y, z], i}"],
    impulses       => ["Vert lines from y=0 or z=0 to point",   "[x], y; {[x, y], z}"],
    labels         => ["Text at given location",                "x, y, str; {x, y, z, str}"],
    lines          => ["Simple line plot",                      "[x], y; {[x, y], z}"],
    linespoints    => ["Lines with symbols at points",          "[x], y; {[x, y], z}"],
    points         => ["Small symbol at each point",            "[x], y; {[x, y], z}"],
    rgbimage       => ["RGB image: 2D with R,G,B",              "[x, y], r,g,b;   {[x, y, z], r,g,b}"],
    rgbalpha       => ["RGBA image: 2D with R,G,B,A",           "[x, y], r,g,b,a; {[x, y, z], r,g,b,a}"],
    steps          => ["steps (Y last; cf fsteps, histeps)",    "[x], y"],
    vectors        => ["Plot a vector field",                   "x, y, dx, dy; {x, y, z, dx, dy, dz}"],
    xerrorbars     => ["Whisker errorbars in X",                "x, y, dx;   x, y, xlo, xhi"],
    xyerrorbars    => ["Whisker errorbars in X & Y",            "x, y, dx, dy; x, y, xlo, xhi, ylo, yhi"],
    yerrorbars     => ["Whisker errorbars in Y",                "x, y, dy;   x, y, ylo, yhi"],
    xerrorlines    => ["Whisker errorbars in X, connected",     "x, y, dx;   x, y, xlo, xhi"],
    xyerrorlines   => ["Whisker errorbars in X & Y, connected", "x, y, dx, dy; x, y, xlo, xhi, ylo, yhi"],
    yerrorlines    => ["Whisker errorbars in Y, connected",     "x, y, dy;   x, y, ylo, yhi"],
    pm3d           => ["Colored 3-D surface plot",              "{[x,y,z],[i]}"]
};
    

our $plotStyleAbbrevs = _gen_abbrev_list(keys %$plotStyleProps);
# Make some tweaks to the abbreviations...
map { $plotStyleAbbrevs->{$_} = 'lines' } qw/ li lin line lines /;
$plotStyleAbbrevs->{box} = 'boxes';
$plotStyleAbbrevs->{lp} = 'linespoints';
map { $plotStyleAbbrevs->{$_} = 'histeps' } qw/ hs hi his hist /;


##############################
# palettesTab - this is a table mapping palette names to rgb specifications in gnuplot, together
# with the color model they support.
#
# From gnuplot's "show palette rgbformulae" command, there are 37 different available rgb color mapping formulae;
# these are used where possible, but defined palettes can also be used.
#
# These codes are used in the parser/emitter codes for the "clut" pseudo-option.
# 
# Each value is an array ref containing (color model),(palette string).
#
# For reference, the formulae in the 'rgbformulae' option, at least in Gnuplot 4.4, are:
# 
#             0: 0               1: 0.5             2: 1              
#             3: x               4: x^2             5: x^3            
#             6: x^4             7: sqrt(x)         8: sqrt(sqrt(x))  
#             9: sin(90x)       10: cos(90x)       11: |x-0.5|        
#            12: (2x-1)^2       13: sin(180x)      14: |cos(180x)|    
#            15: sin(360x)      16: cos(360x)      17: |sin(360x)|    
#            18: |cos(360x)|    19: |sin(720x)|    20: |cos(720x)|    
#            21: 3x             22: 3x-1           23: 3x-2           
#            24: |3x-1|         25: |3x-2|         26: (3x-1)/2       
#            27: (3x-2)/2       28: |(3x-1)/2|     29: |(3x-2)/2|     
#            30: x/0.32-0.78125 31: 2*x-0.84       32: 4x;1;-2x+1.84;x/0.08-11.5
#            33: |2*x - 0.5|    34: 2*x            35: 2*x - 0.5      
#            36: 2*x - 1        

$palettesTab = {
    default  => [ undef, undef,   		         "default palette assigned by Gnuplot" ],
    grey     => [ undef, 'gray',	                 "gray" ],
    gray     => [ undef, 'gray',	                 "gray" ],
    sepia    => [ 'RGB', 'color rgbformulae 7,3,4',      "a simple sepiatone" ],
    grepia   => [ 'RGB', 'color rgbformulae 3,7,4',      "a simple sepiatone, in green" ],
    blepia   => [ 'RGB', 'color rgbformulae 4,3,7',      "a simple sepiatone, in cyan/blue"],
    vepia    => [ 'RGB', 'color rgbformulae 3,4,7',      "a simple sepiatone, in violet" ],
    pm3d     => [ 'RGB', 'color rgbformulae 7,5,15',     "black-blue-red-yellow" ],
    grv      => [ 'RGB', 'color rgbformulae 3,11,6',     "green-red-violet" ],
    ocean    => [ 'RGB', 'color rgbformulae 23,28,3',    "green-blue-white" ],
    gback    => [ 'RGB', 'color rgbformulae 31,31,32',   "printable on a gray background" ],
    rainbow  => [ 'RGB', 'color rgbformulae -33,-13,-10',"Rainbow red-yellow-green-blue" ],
    heat1    => [ 'RGB', 'color rgbformulae 21,22,23',   "heat-map: black-red-yellow-white" ],
    heat2    => [ 'RGB', 'color rgbformulae 34, 35, 36', "heat-map (AFM): black-red-yellow-white" ],
    wheel    => [ 'HSV', 'color rgbformulae 3,2,2',      "hue map: color wheel" ],
};


##############################
# _parseOptHash
#
# Internal routine to parse a collection of options, given a collection of syntax
# definitions and either an options hash ref or a listified hash.
# Used for parsing/adding plot options...
#
# Call with the options hash to be written to, then with the Opt list ref (e.g. $pOpt global above),
# then with the arguments.  The $me is needed to feed to special-handling subs in the 
# OptionsTable.

# _pOHTable: helper for _parseOptHash - handles the individual cases.  Each sub 
# gets ($oldval, $param, $opts) and returns the parsed value (or barfs).

our $_pOHInputs; # table of parser code snippets (declared at bottom)
 
sub _parseOptHash {
    my($options)   = shift || {};
    my($OptTable, $AbbrevTable, $name) = @{shift()};
    my @opts  = @_;

    # Parse arguments one at a time.  If the first one is a hash ref then
    # unpack it inline.  
    opt: while(@opts) {
	# Pull the next key.  If it turns out to be a hash, interpolate the hash into the list
	# of parameters.  If it turns out to be a list, do likewise.  Note that list refs that are
	# in a value slot are *not* interpolated.
	my $k = shift @opts;
	if(ref $k eq 'HASH') {
	    unshift(@opts,%$k);
	    $k = shift @opts;
	} elsif(ref $k eq 'ARRAY') {
	    unshift(@opts,@$k);
	    $k = shift @opts;
	}

	last opt unless defined($k);

	# now pull the value.
	my $v = shift @opts;
	
	# Expand abbreviations and get the table entry for the option
	# (throws an exception on failure)
	my ($kk,$knum) = _expand_abbrev($k, $AbbrevTable, $name); # throws exception on failure

	# Evil DWIMmery.  'N' type parameters take a numeric argument that is
	# allowed to trail the keyword itself in the keyword part of the specifier.
	# So if we got a number we have to check that the corresponding keyword 
	# in fact is 'N' type - else we leave the number in the keyword itself and
	# revalidate.
	if(defined $knum) {
	    if($OptTable->{$kk}->[0] eq 'N') { # HARDWIRED-N parsing
		if(ref $v eq 'ARRAY') {
		    unshift(@$v, $knum);
		} else {
		    $v = [$knum, $v];
		
		}
	    } else {
		$kk = "$kk$knum";
		$knum = undef;
		unless($AbbrevTable->{$kk}) {
		    barf "Error: $name '$k' expanded to '$kk', which isn't a known keyword.\n";
		}
	    }
	}
	
	my $TableEntry = $OptTable->{$kk};

	# Grab a parser code ref...
	my $parser = $TableEntry->[0];
	unless(ref $parser) {
	    my $p = $_pOHInputs->{$parser};
	    unless(ref $p eq 'CODE') {
		barf "Unknown input type '$parser' found in option table entry for $kk! This is a bug.";
	    }
	    $parser = $p;
	} elsif(ref $parser eq 'ARRAY') {
	    # If the parser entry is an array ref, its first element is a regexp to match for
	    # successful enumeration.is treated as an enumerated list of regexps to match
	    # (if it contains scalars) or a sequence of code refs to call (if it contains CODE refs).
	    if(ref($parser->[0]) || (0+@$parser != 1)) {
		barf("HELP!  Parser is confused.  This is a bug, please report it.\n");
	    } else {
		# normal case: a list ref with a single element containing a regexp
		my $a = $parser->[0];
		my $p = sub {
		    my ($old, $newparam, $hash) = @_;
		    if($newparam =~ m/$a/) {
			return $newparam;
		    } else {
			barf("Unknown field $newparam (must match m/$a/)\n");
		    }
		};
		$parser = $p;
	    }
	}

	unless(ref $parser eq 'CODE') {
	    barf "HELP!";
	}

	$options->{$kk} = &$parser($options->{$kk}, $v, $options);
    }
    return $options;
}

##############################
#
# Parse table 
#
# $_pOHInputs describes input parsing from argument lists.  Each key
# is a code for a particular type of input; the value is a subroutine
# that accepts ($old_value, $new_input, $options_hash) and returns the
# parsed new value.

$_pOHInputs = {
    ## Simple cases - boolean, number, scalar
    'b' => sub { ( (defined $_[1]) ? ($_[1] ? 1 : 0) : undef ); },
    'n' => sub { ( (defined $_[1]) ? ($_[1] + 0)     : undef ); },
    's' => sub { ( (defined $_[1]) ? "$_[1]"         : undef ); },

    ## one-line list (can also be boolean)
    'l' => sub { return undef unless(defined $_[1]);
		 return "" unless(length($_[1]));                                 # false value yields false
		 return $_[1] if( (!ref($_[1])) && "$_[1]" =~ m/^\s*\-?\d+\s*$/); # nonzero integers yield true
		 # Not setting a boolean value - it's a list (or a trivial list).
		 if(ref $_[1] eq 'ARRAY') {
		     return $_[1];
		 } else {
#		     return [ split( /\s+/, $_[1] ) ];
		     return [$_[1]];
		 }
                },

    ## cumulative list (delete on "undef")
    'C' => sub { return undef unless(defined $_[1]);
		 return 0 unless($_[1]);                             # false value yields false
		 return 1 if( $_[1] && "$_[1]" =~ m/^\s*-?\d+\s*$/); # nonzero integers yield true
		 # Not setting a boolean value - it's a list, so append it.
		 my $out = (ref $_[0] eq 'ARRAY') ? $_[0] : [];
		 if(ref $_[1] eq 'ARRAY') {
		     push( @$out, $_[1] );
		 } else {
		     push( @$out, [ split ( /\s+/, $_[1] ) ] );
		 }
		 return $out;
                },

    ## set hash values 
    'H' => sub { return undef unless(defined $_[1]);
		 my $out = (ref $_[0] eq 'HASH') ? $_[0] : {};
		 my $in = $_[1];
		 return undef unless defined($in);
		 if(ref($in) eq 'ARRAY') {
		     my %h = (@$in);
		     $in = \%h;
		 }
		 if(ref($in) eq 'HASH') {
		     for my $k(keys %{$_[1]}) {
			 $out->{$k} = $_[1]->{$k};
		     }
		 } else {
		     # scalar or <mumble>...
		     if( $in =~ m/([^\s]+)\s+(.*)$/ ) {
			 # key/value found
			 $out->{$1} = $2;
		     } else {
			 # at most a key found.  If nothing, clear the hash
			 return undef unless($in =~ s/^\s*([^\s]+)\s*$/$1/);
			 # A key was found.  Set a nonempty value so that "set foo $k" gets emitted
			 $out->{$1} = " ";
		     }
		 }
		 return $out;
                },
		
    ## number-indexed list
    ## 
    'N' => sub { my($old,$new,$h) = @_;
		 return undef unless(defined $new);
		 my $out = (ref($old) eq 'ARRAY') ? $old : [];

                 # Split strings into lists if necessary.
                 $new = [ split(/\s+/,$new) ] unless(ref($new) eq 'ARRAY');

                 # Check for nested lists -- multiple specs.
                 if(ref($new->[0]) eq 'ARRAY') {
		     my $o = [];
		     for my $l(@$new) {
			 unless(ref $l eq 'ARRAY') {
			     die "Markup option: nested lists must contain only list refs\n";
			 }
			 push(@$o, [@$l]);
		     }
		     $out = $o;
		 } else {
		     # not a nested list - look for an index number at the start.
		     my $dex;
		     if($new->[0] =~ m/^\s*(\d+)\s*$/) {
			 $dex = 0 + shift(@$new);
		     } else {
			 $dex = scalar(@$out) || 1;
		     }
		     if(@$new) {
			 $out->[$dex] = $new;
		     } else {
			 $out->[$dex] = undef;
		     }
		 }
		 return $out;
    },
    
    ## <foo>tics option list
    ## 
    'lt' => sub { my($old, $new, $h) = @_;
		  return undef unless(defined $new);
		  my $ok = {};
		  for( qw/axis border mirror in out scale rotate offset autofreq locations labels format font rangelimited textcolor/ ) {
		      $ok->{$_} = 1;
		  }

		  my @list = ();

		  if(ref($new) eq 'HASH') {
		      ### Check for extraneous keys...
		      my @notok = ();
		      for(keys %$new) {
			  push(@notok, $_) unless($ok->{$_});
		      }
		      if(@notok) {
			  barf "<foo>tics option: unknown keyword(s): '".join("', '",@notok)."'";
		      }

		      ### All is OK -- proceed to parse...
		      my @list = ();
		      my $bs  = sub { map { push @list, $_ if($new->{$_}) } @_ };

		      &$bs("axis", "border");
		      push(@list, $new->{mirror} ? "mirror" : "nomirror") if( defined($new->{mirror}) );
		      &$bs("in","out");
		      if(defined $new->{scale}) {
			  if(ref $new->{scale} eq 'ARRAY') {
			      push @list, "scale ".join(",",@{$new->{scale}});
			  } else {
			      push(@list, "scale $new->{scale}");
			  }
		      } else {
			  push(@list, "scale default");
		      }
		      if(defined $new->{rotate}) {
			  unless($new->{rotate}) {
			      push(@list, "norotate");
			  } else {
			      push(@list, "rotate by ".$new->{rotate});
			  }
		      }
		      if(defined $new->{offset}) {
			  unless($new->{offset}) {
			      push(@list, "nooffset");
			  } else {
			      unless(ref($new->{offset}) eq 'ARRAY') {
				  barf "<foo>tics option: 'offset' suboption must have a list ref value or be zero";
			      } else {
				  push(@list, "offset ".join(",",@{$new->{offset}}));
			      }
			  }
		      }
		      if(defined $new->{locations}) {
			  unless(ref($new->{locations}) eq 'ARRAY') {
			      barf "<foo>tics option: 'locations' suboption must contain a list ref";
			  } else {
			      push(@list, join(",",@{$new->{locations}}));
			  }
		      } 
		      if(defined $new->{labels}) {
			  unless(ref($new->{labels}) eq 'ARRAY') {
			      barf "<foo>tics labels option: must contain a list ref";
			  } else {
			      push(@list, "(", join(", ",
					       map {
						   barf "<foo>tics: labels list elements must be duals or triples as list refs"  unless(ref $_ eq 'ARRAY');
						   sprintf('"%s" %s %s', $_->[0]//"", $_->[1]//0, $_->[2]//"");
					       
					       } @{$new->{labels}}
					       ),
				   ")"
				  );
			  }
		      }
		      if(defined $new->{format}) {
			  push(@list, 'format', "\"$new->{format}\"");
		      }
		      if(defined $new->{font}) {
			  if(ref $new->{font} eq 'ARRAY') {
			      push(@list, "font", '"'.join(',',@{$new->{font}}).'"');
			  } else {
			      push(@list, "font",'"'.$new->{font}.'"');
			  }
		      }
		      &$bs('rangelimited');
		      if(defined $new->{textcolor}) {
			  # parse a colorspec -- probably needs to be broken out to a routine...
			  my ($s, $ss);
			  if(ref($new->{textcolor}) eq 'ARRAY') {
			      $s = shift @{$new->{textcolor}};
			      $ss = join(" ",@{$new->{textcolor}});
			  } else {
			      $s = $new->{textcolor};
			      $s =~ s/^\s*//;
			      $s =~ s/\s(.*)// && ($ss = $1);
			  }
			  if($s =~ m/^r(g(b(c(o(l(o(r)?)?)?)?)?)?)?\s*$/) { # rgbcolor case 
			      if($ss =~ m/\s*variable\s*/) {
				  push(@list, "rgbcolor variable");
			      } else {
				  push(@list, "rgbcolor \"$ss\"");
			      }
			  } elsif($s =~ m/^p(a(l(e(t(t(e)?)?)?)?)?)?\s*$/) { # palette case
			      push(@list, "palette $ss");
			  } else {
			      barf("<foo>tics option: textcolor appears not to contain a colorspec");
			  }
		      }
		      return \@list;
		  }

		  unless(ref($new) eq 'ARRAY') {
		      $new = [split /\s+/, $new];
		  }

		  if( grep( (ref $_), @$new) ) {
		      barf("<foo>tics: if you specify an array it must contain only strings or numeric\n   values.  Consider using a hash ref instead, as hash values are parsed.\n");
		  } 

		  print STDERR "PDL::Graphics::Gnuplot: <foo>tics: WARNING: using deprecated list ref form.\n";

		  @list = @$new;
		  return \@list;
    }
};




##############################
# _emitOpts 
#
# Accepts an options table as a single hash ref, and emits a corresponding
# string that is suitable for passing on to gnuplot.  Curve options and 
# plot options use different output specifiers and can therefore both be
# handled by one routine.
#
# Because curve and plot options have different parse tables, you have to 
# pass in the parse table ref appropriate to the type of option you're emitting.

sub _emitOpts {
    my ($options, $tab, $this) = @_;
    my $table = $tab->[0];
    our $_OptionEmitters;
    
    # Sort the keys into options table order -- this is so that keys that are supposed
    # to be up top go up top; keys with no particular order defined in the parse table 
    # are allowed to stay in random order.
    #
    # Keys that are supposed to be at bottom (if any in future) can be 
    # placed there by the expedient of assigning them sort values in excess of 1,000.
    #
    my @keys = sort { ((defined $table->{$a}->[3])?($table->{$a}->[3]): 999) <=> ((defined $table->{$b}->[3])?($table->{$b}->[3]):999) or  
			  ($a cmp $b) 
                    } keys %$options;

    my $s = "";
    

    # Loop over the keys and emit.
    key: while(@keys) {
	my $k = shift @keys;

	my $tableEntry = $table->{$k};
	if(!defined($tableEntry)) {
	    barf "_emitOpts: bad table entry for keyword '$k'";
	}

	## Cheesy ordering logic here -- if the parse table indicates that we have to go after 
	## a particular option, walk back from the end until we find one of them or get to the 
	## front of the queue.  If we find a match, we splice the current one back there and move 
	## on to the next key.
	if($tableEntry->[2]) {
	    my %h = (map { ($_, 1) } @{$tableEntry->[2]});  # make a hash of later-than keywords, with 1 in each entry
	    for my $i(reverse 0..$#keys) {
		if($h{$keys[$i]}) {
		    splice(@keys,$i+1,0,$k);
		    next key;
		}
	    }
	}
	
	## Rubber meets the road -- call the corresponding output function
	my $emitter = $tableEntry->[1] || " ";
	unless(ref $emitter) {
	    my $o = $_OptionEmitters->{$emitter};
	    unless( ref $o eq 'CODE') {
		barf "Unknown output type '$emitter' found in option table entry for $k!";
	    }
	    $emitter = $o;
	} elsif(ref $emitter ne 'CODE') {
	    barf 'PLEH!';
	}

	$s .= &$emitter($k, $options->{$k}, $options, $this)
    }

    return $s;
}

##############################
# 
# Emission table
#
# $_OptionEmitters describes how to emit stored parameters.  Each
# key is a code for a particular type of output; the value is a subroutine
# that returns the outputted parameter as a string.
#
# Different codes emit whole lines (e.g. for setting plot options) or
# space-delimited words (e.g. for setting curve options).  Curve
# option emitters have codes that start with 'c'.
#
# Although most of the emitters take just (keyword, value, options-hash), 
# they may take a fourth parameter containing the complete object.
# That's useful for things like "crange", which needs to know the global
# options state to know how to emit itself.

our $_OptionEmitters = {
    #### Default output -- a collection of terms with spaces between them as a plot option
    ' ' => sub { my($k,$v,$h) = @_; 
		 return "" unless(defined($v));
		 if(ref $v eq 'ARRAY') {
		     return join(" ",("set",$k,map { (defined $_)?$_:"" } @$v))."\n";
		 } elsif(ref $v eq 'HASH') {
		     return join(" ",("set",$k,%$v))."\n";
		 } else {
		     return join(" ",("set",$k,$v))."\n";
		 }
                },

    #### nomulti -- a default style plot option that is ignored in multiplot mode
    'nomulti' => sub { my($k,$v,$h) = @_; 
		 return "" unless((defined($v)) and !($h->{multiplot}));
		 if(ref $v eq 'ARRAY') {
		     return join(" ",("set",$k,map { (defined $_)?$_:"" } @$v))."\n";
		 } elsif(ref $v eq 'HASH') {
		     return join(" ",("set",$k,%$v))."\n";
		 } else {
		     return join(" ",("set",$k,$v))."\n";
		 }
                },

    #### Empty output - return nothing.
    '-' => sub { "" },

    #### A quoted scalar value as a plot option
    'q' => sub { my($k,$v,$h) = @_;
		 return "" unless(defined($v));
		 return "unset $k\n" unless(length($v));
		 return "set $k \"$v\"\n";
                },

    #### A quoted scalar value as a plot option, not emitted in multiplot mode
    'qnm' => sub { my($k,$v,$h) = @_;
		 return "" unless((defined($v) and !($h->{multiplot})));
		 return "unset $k\n" unless(length($v));
		 return "set $k \"$v\"\n";
                },

    #### A quoted scalar value as a curve option
    'cq' => sub { my($k,$v,$h) = @_;
		  return "" unless(defined($v));
		  return " $k \"$v\" ";
    },

    #### A value with no associated keyword
    'cv' => sub { my($k,$v,$h) = @_;
		  return " $v " if(defined($v));
		  return "";
    },

    #### A nonquoted scalar value as a plot option
    's' => sub { my($k,$v,$h) = @_;
		 return "" unless(defined($v));
		 return "unset $k\n" unless(length($v));
		 return "set $k" if($v eq ' ');
		 return "set $k \"$v\"\n";
                },

    #### A nonquoted scalar value as a curve option
    'cs' => sub { my($k,$v,$h) = @_;
		  return "" unless(defined($v));
		  return " $k $v ";
    },

    ### A curve flag in one word
    'cf' => sub { my($k,$v,$h) = @_;
		  return "" unless(defined($v));
		  return " no$k " unless($v);
		  return " $k ";
    },
    'cff'=> sub { my($k, $v, $h) = @_;
		  return "" unless($v);
		  return " $k ";
    },
   
    ### A size specification (used in terminal options in the constructor, see $termTab)
    ### generally a list with (width, height, [units]) in it.  Should have been parsed as an 'l'.
    'csize'=> sub { my($k, $v, $h) = @_;
		    our $lConv; # unit conversion hash (see below)
		    return "" unless($v and @$v);
		    my @v = @$v;
		    my $conv = 1;
		    if($h->{__unit__}) {
			if($lConv->{$h->{__unit__}}) {
			    $conv *= $lConv->{$h->{__unit__}};
			} else {
			    die "Uh-oh -- csize parser found an error -- table says default units are '$h->{__unit__}' but that's no unit!\n";
			}
		    }
		    # If there's a unit spec at the end, pop if off and accumulate the conversion factor
		    if($lConv->{$v[$#v]}) {
			$conv /= $lConv->{ pop @v };
		    }
		    if(@v==1) {
			@v = ($v[0],$v[0]);
		    }
		    if(@v > 2) {
			die "Too many values, or an unrecognized unit, in size spec '".join(",",@$v)."'\n";
		    }
		    return( " size ".($v[0]*$conv).",".$v[1]*$conv." " );

    },
			

    #### A boolean value as a plot option
    'b' => sub { my($k,$v,$h) = @_;
		 return "" unless defined($v);
		 return $v ? "set $k\n" : "unset $k\n";
                },

    #### A boolean or 'time' (for <foo>data plot options)
    'bt' => sub { my($k,$v,$h) = @_;
		  return "set $k\n" unless ($v // ""  and  $v=~m/^t/i);
		  return "set $k $v\n";rxt hel
                 },

    #### A space-separated collection of terms as a plot option
    'l' => sub { my($k,$v,$h) = @_;
		 return "" unless(defined($v));
		 if(ref $v eq 'ARRAY') {
		     return "set $k ".join(" ",@$v)."\n";
		 } elsif(ref $v eq 'HASH') {
		     barf "hash value found for comma-separated list option '$k' -- not allowed";
		 } else {
		     return $v ? "set $k\n" : "unset $k\n";
		 }
                },

    ## one-line list with leading quoted string (e.g. for titles)
    'ql' => 
		    sub { my($k,$v,$h) = @_;
			  unless(ref $v eq 'ARRAY') {
			      return ( (length($v) eq 0) ? "unset $k\n" : "set $k \"$v\"\n");
			  }
			  my $quoted = $v->[0];
			  return sprintf('set %s "%s" %s%s',$k,$quoted,join(" ",@{$v}[1..$#$v]),"\n");
		    },

    #### A space-separated collection of terms as a curve option
    'cl' => sub { my($k,$v,$h) = @_;
		  return "" unless defined($v);
		  return " $k $v " unless(ref $v eq 'ARRAY');
		  return join(" ",("",$k,@$v,""));
    },

    #### A comma-separated (rather than space-separated) collection of terms
    ',' => sub { my($k,$v,$h) = @_;
		 return "" unless(defined($v));
		 if(ref $v eq 'ARRAY') {
		     return "set $k ".join(",",@$v)."\n";
		 } elsif(ref $v eq 'HASH') {
		     barf "hash value found for comma-separated list option '$k' -- not allowed";
		 } else {
		     return $v ? "set $k\n" : "unset $k\n";
		 }
                },

    #### A comma-separated collection of terms as a curve option
    'c,' => sub { my($k,$v,$h) = @_;
		 return "" unless(defined($v));
		 if(ref $v eq 'ARRAY') {
		     return " ".join(",",@$v)." ";
		 } 
		 return " $v ";
    },

    #### A collection of values, reported one per line
    '1' => sub { my($k,$v,$h) = @_;
		 return "" unless(defined $v);
		 if((ref $v) eq 'ARRAY') {
		     return join("", map { defined($_) ? "set $k $_\n" : "" } @$v);
		 } elsif((ref $v) eq 'HASH') {
		     barf "hash value found for one-per-line list option '$k' -- not allowed";
		 } else {
		     return $v ? "set $k\n" : "unset $k\n";
		 }
               },

    #### A set of sub-keywords each of which may contain a list of terms
    "H" => sub { my($k,$v,$h) = @_;
		 return "" unless(defined $v);
		 if(ref $v eq 'ARRAY') {
		     barf "array value found for hash option '$k' -- not allowed";
		 } elsif(ref($v) eq 'HASH') {
		     return "set $k\n" unless(keys(%$v));
		     return join("", map { my $l = "";
					   if(defined($v->{$_})) {
					       unless($v->{$_}) {
						   $l = "unset $k $_\n";
					       } elsif(ref $v->{$_} eq 'ARRAY') {
						   $l = "set $k $_ ".join(" ",@{$v->{$_}})."\n";
					       } elsif(ref $v->{$_} eq 'HASH') {
						   barf "Nested hashes not allowed in hash option '$k'";
					       } else {
						   $l = "set $k $_ $v->{$_}\n";
					       }
					   }
					   $l;
				 } 
				 sort keys %$v
			 );
		 } else {
		     barf "scalar value '$v' not allowed for hash option '$k'";
		 }
                },

    "HNM" => sub { my($k,$v,$h) = @_;
		   return "" unless((defined $v) and !($h->{multiplot}));
		   if(ref $v eq 'ARRAY') {
		       barf "array value found for hash option '$k' -- not allowed";
		   } elsif(ref($v) eq 'HASH') {
		       return "set $k\n" unless(keys(%$v));
		       return join("", map { my $l = "";
					     if(defined($v->{$_})) {
						 unless($v->{$_}) {
						     $l = "unset $k $_\n";
						 } elsif(ref $v->{$_} eq 'ARRAY') {
						     $l = "set $k $_ ".join(" ",@{$v->{$_}})."\n";
						 } elsif(ref $v->{$_} eq 'HASH') {
						     barf "Nested hashes not allowed in hash option '$k'";
						 } else {
						     $l = "set $k $_ $v->{$_}\n";
						 }
					     }
					     $l;
				   } 
				   sort keys %$v
			   );
		   } else {
		       barf "scalar value '$v' not allowed for hash option '$k'";
		   }
    },

    #### A collection of numbered specifiers (e.g. "arrow"), each with a collection of terms
    "N" => sub { my($k,$v,$h) = @_;
		 return "" unless(defined $v);
		 if(ref $v ne 'ARRAY') {
		     barf "non-array value '$v' found for numeric-indexed option '$k' -- not allowed";
		 }
		 return join ("", map { my $l;
					if(defined($v->[$_])) {
					    $l = "set   $k $_ ";
					    if(ref $v->[$_] eq 'ARRAY') {
						$l .= join(" ",@{$v->[$_]});
					    } elsif(ref $v->[$_] eq 'HASH') {
						$l .= join(" ",(%{$v->[$_]}));
					    } else {
						$l .= $v->[$_];
					    }
					    $l .= "\n";
					} else {
					    $l = "unset $k $_\n";
					}
					$l;
			      } (1..$#$v)
		     );
                 },

    #### A collection of numbered specifiers for "object" types - requires a special case for
    #### "set object polygon"
    "NO" => sub { my($k,$v,$h) = @_;
		 return "" unless(defined $v);
		 if(ref $v ne 'ARRAY') {
		     barf "non-array value '$v' found for numeric-indexed option '$k' -- not allowed";
		 }
		 my $s = join ("", map { my $l;
					if(defined($v->[$_])) {
					    $l = "set   $k $_ ";
					    if(ref $v->[$_] eq 'ARRAY') {
						$l .= join(" ",@{$v->[$_]});
					    } elsif(ref $v->[$_] eq 'HASH') {
						$l .= join(" ",(%{$v->[$_]}));
					    } else {
						$l .= $v->[$_];
					    }
					    $l .= "\n";
					} else {
					    $l = "unset $k $_\n";
					}
					$l;
			      } (1..$#$v)
		     );
		  #Split polygon lines after the polygon spec - yuck.
		  my @s = split ("\n",$s);
		  for my $i(0..$#s){
		      if($s[$i] =~ s/((set +\w+ +\d+) +p(o(l(y(g(o(n)?)?)?)?)?)? +from +-?\d+(\.\d+)?([eE]?\-?\d+)?\,-?\d+(\.\d+)?([eE]?\-?\d+)?( +to +-?\d+(\.\d+)?([eE]?\-?\d+)?\,-?\d+(\.\d+)?([eE]?\-?\d+)?)+ +)//) {
		      $s[$i] =  $1."\n".$2." ".$s[$i];
		      }
		  }
		  return join("\n",@s,"");
                 },
    #### A collection of numbered specifiers, the first word of which is quoted (for labels).
    "NL" => sub { my($k,$v,$h) = @_;
		 return "" unless(defined $v);
		 if(ref $v ne 'ARRAY') {
		     barf "non-array value '$v' found for numeric-indexed option '$k' -- not allowed";
		 }
		 return join ("", map { my $l;
					if(defined($v->[$_])) {
					    $l = "set   $k $_ ";
					    if(ref $v->[$_] eq 'ARRAY') {                      # It's an array
						$v->[$_]->[0] = "\"$v->[$_]->[0]\""            # quote the first element
						    unless($v->[$_]->[0] =~ m/^\".*\"$/);      # unless it's already quoted
						$l .= join(" ", map {                          
						    (ref($_) eq 'ARRAY') ? join(",",@$_) : $_; # Nested arrays get connected with ','
							   } @{$v->[$_]});
					    } elsif(ref $v->[$_] eq 'HASH') {
						$l .= join(" ",(%{$v->[$_]}));
					    } else {
						$l .= $v->[$_];
					    }
					    $l .= "\n";
					} else {
					    $l = "unset $k $_\n";
					}
					$l;
			      } (1..$#$v)
		     );
                 },
    
    #### Ranges can either be given as a list, the first two elements
    #### of which are the range and the rest of which are options, or
    #### as a list, the first element of which is a gnuplot range
    #### specifier and the rest of which are options, or as a string
    #### that combines everything.
    ####
    #### The job is complicated by the fact that the 'restore' keyword
    #### can replace the normal range specifier.
    #### 
    #### Note: we don't try to do a perfect job of parsing, only to
    #### decide which parse fixing-up style is needed to send
    #### something reasonable to gnuplot in the correct case.  Gnuplot
    #### is expected to throw an error if something is broken.


    "range" => sub { my($k,$v,$h) = @_;    
		     return "" unless(defined $v);

		     # scalar -- treat it as a string containing the whole command.
		     return "set $k $v\n" if(ref $v ne 'ARRAY');


		     #looks like 'set <foo>range restore' (only way 'r' can be the first char)
		     return "set $k ".join(" ",@$v)."\n" if(($v->[0] // '') =~ m/^\s*r/i);


		     # first element is an empty range specifier - emit.
		     return "set $k ".join(" ",@$v)."\n" if(($v->[0] // '') =~ m/\s*\[\s*\]/);

		     my $c = substr($k,0,1);
		     my $tfmt = ( $h->{$c."data"} // "" ) =~ m/time/;
		     
		     # first element has a nonempty range specifier (naked or not).
		     if(($v->[0] // '') =~ m/\:/) {
			 $v->[0]=~ s/^\s*((.*[^\s])?)\s*$/$1/; # trim leading and trailing whitespace if present

			 unless($v->[0] =~ m/^\[/) {
			     # the first char was not a '['; assume it is a naked range and patch accordingly.
			     $v->[0] = "[$v->[0]]";
			 }
			 
			 if($tfmt) {
			     # Make sure we have quotes as necessary
			     $v->[0] =~ s/\[([^\"\:\*]+)\:/\[\"$1\"\:/;
			     $v->[0] =~ s/\:([^\"\:\*]+)\]/\:\"$1\"\]/;
			 }
			 my $s = join(" ",@$v);
			 $s =~ s/\[\:/\[*\:/;
			 $s =~ s/\:\]/\:*\]/;

			 return "set $k $s\n";
		     }
		     # If we got here, the first element has no ':'.  Treat the first two elements as numbers and make a range 
		     # specifier out of 'em, then emit.
		     # Here's a little fillip: gnuplot requires quotes around time ranges
		     # if the corresponding axes are time data.  Handle that bizarre case.
		     if( ($h->{$c."data"} // "" ) =~ m/time/ ) {
			 return sprintf("set %s [%s:%s]\n",$k, ((defined $v->[0])?"\"$v->[0]\"":"*"), ((defined $v->[1])?"\"$v->[1]\"":"*"));
		     }
	
		     return sprintf("set %s [%s:%s] %s\n", $k, ((defined $v->[0])?$v->[0]:"*"), ((defined $v->[1])?$v->[1]:"*"), join(" ",@{$v}[2..$#$v]));
    },

    "crange" => sub { my($k,$v,$h, $this) = @_;
		      return "" unless(defined $v);
		      return "$v" if(ref $v ne 'ARRAY');
		      my $of = 946684800.0;
		      # Here's a little fillip: gnuplot requires quotes around time ranges
		      # if the corresponding axes are time data.  Handle that bizarre case.
		      my $c = substr($k,0,1);

		      if( (($this and $this->{options} and $this->{options}->{$c."data"}) // "" ) =~ m/time/ ) {
			  print STDERR "WARNING: gnuplot-4.6.1 date range bug triggered.  Check the date scale.\n";
			  return sprintf(" [%s:%s] ",((defined $v->[0])?"\"$v->[0]\"":""), ((defined $v->[1])?"\"$v->[1]\"":""));
		      }
		      return sprintf(" [%s:%s] ",((defined $v->[0])?$v->[0]:""), ((defined $v->[1])?$v->[1]:""));
    },

};

##############################
# termTab - list of supported terminals and their arguments
# Each entry is a hash ref containing:
#   opt - specification hash for the options for this terminal
#   unit - native unit in which size is specified for this terminal
#   desc - a one-line description of the terminal
#
# Since there are so many terminal types, with so many slightly 
# different syntaxes, we store them in shorthand here.  The
# $termTab_types table contains commonly used parameter keywords,
# together with partial hash parser table entries.  The
# actual terminal descriptions then refer to those keywords
# wherever possible rather than repeating the whole definition.
#

my $emit_enh = sub { my ($k,$v,$h) = @_; return " ".($v?"":"no")."enhanced "; };

our $lConv = {
    inch  => 1,
    inc   => 1,
    in    => 1,
    i     => 1,
    char  => 16,
    cha   => 16,
    ch    => 16,
    c     => 16,
    pt    => 72,
    points=> 72,
    point => 72,
    poin  => 72,
    poi   => 72,
    po    => 72,
    px    => 100,
    pixels=>100,
    pixel => 100,
    pixe  => 100,
    pix   => 100,
    pi    => 100,
    p     => 100,

    mm    => 25.4,
    cm    => 2.54
};

# These are keyed descriptors for options that are used in at least two devices. They are invoked by name in the 
# $termTab_source table below, which describes all the known gnuplot device specification options.
our $termTab_types = {
    output     => ['s','q',     "File name for output"],                 # autocopied to a plot option when present for a device
    output_    => ['s','cv',    "Window number for persistent windows"], # trailing '_' prevents autocopy to a plot option
    title      => ['s','cq',    "Window title"],
    size       => ['l','csize', "Window size (default unit is %u)"],
    font       => ['s','cq',    "Font to use ('<fontname>,<size>')"],
    fontsize   => ['s','cs',    "Font size (points)"],                      # use for devices that use no keyword for font size
    enhanced   => ['b','cf',    "Enable or disable gnuplot enhanced text escapes for markup"],
    color      => ['b','cff',   "Generate a color plot (see 'monochrome') if true"],
    monochrome => ['b','cff',   "Generate a B/W plot (see 'color') if true"],
    solid      => ['b','cff',   "Plot only solid lines (see 'dashed') if true"],
    dashed     => ['b','cff',   "Plot dashed lines (see 'solid') if true"],
    rotate     => ['b','cf',    "Enable or disable true rotated text (90 degrees)"],
    linewidth  => ['s','cs',    "Multiplier on line width (typ. default 1 pt)"],
    dashlength => ['s','cs',    "Multiplier on dash length for dashed plots"],
    standalone => ['b','cff',   "Generate postscript that can render alone (see 'input')"], # for LaTeX devices
    input      => ['b','cff',   "Generate postscript to be combined with LaTeX output"],    # for LaTeX devices
    level1     => ['b','cff',   "Generate Level 1 Postscript (see 'leveldefault')"],        # for PostScript devices
    leveldefault=>['b','cff',   "Generate full-featured Postscript (see 'level1')"],        # for PostScript devices
    rounded    => ['b','cff',   "Generate rounded ends on lines (see 'butt')"],
    butt       => ['b','cff',   "Generate butt-ends on lines (see 'rounded')"],
    clip       => ['b','cf',    "Clip output to bounding box (or not)"],                    # for PostScript devices
    landscape  => ['b','cff',   "Set landscape orientation (see 'portrait')"],
    portrait   => ['b','cff',   "Set portrait orientation (see 'landscape')"],
    tiny       => ['b','cff',   "Set tiny preset plot size (see also 'size')"],
    small      => ['b','cff',   "Set small preset plot size (see also 'size')"],
    medium     => ['b','cff',   "Set medium preset plot size (see also 'size')"],
    big        => ['b','cff',   "Set big preset plot size (see also 'size')"],
    large      => ['b','cff',   "Set large preset plot size (see also 'size')"],
    giant      => ['b','cff',   "Set giant preset plot size (see also 'size')"],
    transparent=> ['b','cf',    "Enable or disable transparency for the background"],
    background => ['s','cv',    "Background color in xRRGGBB format ('x' literal)"],    
    interlace  => ['s','cf',    "Enable or disable interlaced encoding of image"],         # JPEG and PNG
    crop       => ['b','cf',    "Enable or disable autocropping to first drawn pixel"],
    oldstyle   => ['b','cff',   "Force old-style text spacing (deprecated)"],
    newstyle   => ['b','cff',   "Force new-style text spacing (default; see 'oldstyle')"],
    auxfile    => ['b','cf',    "Generate (or not) an auxiliary .aux file for LaTeX"],
    persist    => ['b','cf',    'enable (or disable) persistence after plotting is done'],
    raise      => ['b','cf',    'enable (or disable) raising the display window to the top']
};    

# This table includes all terminals named in the gnuplot 4.4 documentation.  Unsupported terminals have 
# only a description string; supported terminals get a hash that contains:
#   - unit (default size unit for the terminal)
#   - desc (description string)
#   - opt  (array ref containing option descriptors in order).
# Each option descriptor is one of:
#       * a string indexing the descriptor in $termTab_types, above, or
#       * an array ref containing:
#               -name
#               -input parser (as for $pOptionsTable)
#               -output parser (as for $pOptionsTable)
#               -description string

our $termTabSource = {
    'aed767'   => "AED graphics terminal                  [NS: ancient]",
    'aifm'     => "Adobe Illustrator                      [NS: obsolete (use pdf)]",
    'amiga'    => "Amiga terminal driver                  [NS: ancient]",
    'apollo'   => "Apollo terminal driver                 [NS: ancient]",
    'aqua'     => { unit=>'pt', desc=> 'Aqua terminal program on MacOS X (MacOS default device)', int=>1, ok=>1,
		  opt=>[ qw/ output_ title size font enhanced / ]},
    'be'       => "BeOS/X11 (Ah, Be, how we miss thee)    [NS: ancient]",
    'canvas'   => { unit=>'pt', desc=> "Output Javascript Canvas rendering code.",
		    opt=>[ 'size', 
			       # custom line shields user from "fsize/fontsize"
			   ['fontsize', 's', sub { " fsize $_[1] "}, "Font size (points)"],  
			   'enhanced', 
			   'linewidth', 
			   ['standalone', 'b','cff',  "Generate a standalone html page (default) (see 'name')"],
			   ['mousing',    'b','cff',  "Make a mouse-tracking box underneath the plot"],
			   ['name',       's','cq',   "Generate a javascript subroutine named 'name'"],
			   ['jsdir',      's','cq',   "URL of directory where javascripts are found"],
			   'title']},

    'cgi'      => "SCO CGI drivers.                       [NS: ancient/evil]",
    'cgm'      => { unit=>'pt', desc=> "Computer Graphic Metafile format (ANSI X3.122-1986)",
		    opt=>[ qw/ color monochrome solid dashed rotate /,
			   ['size',  'l', sub { my( $k, $v, $h) = @_; 
						my $conv = 1;
						if(@$v > 2) {
						    printf STDERR "Warning: cgm device ignores height spec; using width only.";
						} 
						if(@$v >= 2) {
						    if($lConv->{$v->[$#$v]}) {
							$conv = $lConv->{ $v->[$#$v] } / $lConv->{ 'pt' };
						    } elsif( $v>2 ) {
							die "cgm device: 3-element size spec must end with a unit spec";
						    }
						}
						return " ".($v->[0] * $conv)." ";
			                     }, 
			                     "Window size (default unit is pt; height is ignored)"
			                   ],
			   'linewidth',
			   ['font',   's','cq','Font ("<fontname>,<size>") - NOT system fonts - see manual for list'],
			   'output']},
    'corel'  => "Corel Draw                             [NS: ancient]",
    'debug'  => "Gnuplot internal debugging mode        [NS: not useful]",
    'dospc'  => "Generic PC VESA/VGA/XGA direct display [NS: obsolete]",
    'dumb'   => {
	unit=>'char',desc=>"dumb terminal (ASCII output)",ok=>1,
	opt=>[ ['feed','b','cf',"Issue (or not) a formfeed at the end of each plot"],
			qw/ size enhanced output /]},
    'dxf'    => {unit=>'pt', desc=>"AutoCad 10.x interchange files",
		 opt=>[ 'output' ]},
    'dxy800a'=> "Roland DXY800A Plotter                 [NS: obsolete]",
    'eepic'  => {unit=>'in',desc=>"LaTeX picture (alternative w/ epic.sty & eepic.sty)",
		 opt=>[ qw/ color dashed rotate small tiny /, 
			['fontsize','s','cv','Font size (points)'], # special entry 'coz eepic wants no "fontsize" keyword
			'output']},
    'emf'    => {unit=>'pt',desc=>"Microsoft Windows Enhanced Metafile Format",
		 opt=>[ qw/ color monochrome solid dashed enhanced /,
			['noproportional','b','cff',"(only with 'enhanced') - disable proportional font spacing"],
			qw/ linewidth dashlength size output /]},
    'epslatex'=>{unit=>'in',desc=>"Encapsulated PostScript with LaTeX text segments",
		 opt=>[ qw/standalone input oldstyle newstyle level1 leveldefault color monochrome/,
			qw/solid dashed dashlength linewidth rounded butt clip size font output/]
    },
    'excl'   => "Talaris printer support                [NS: ancient]",
    'fig'    => {unit=>'in',desc=>"Fig graphics language output",
		 opt=>[ qw/ color monochrome landscape portrait small big size /,
			['pointsmax',  's','cs', "maximum number of points per polyline (default 2000)"],
			qw/ solid dashed /,
			['font','s', sub { my($k,$v,$h)=@_;                   # special entry to allow standard format 
					   my($f,$fs)=split /,/,$v;           # (fig requires breaking font name and 
					   my($s) = $f ? " font $f " : "";    # size out into different keywords)
					   $s .= "fontsize $fs " if ($fs);
					   return $s;
			                 }, 
			                         "Font to use ('<fontname>,<size>')"],
			'fontsize',
			['textnormal', 'b','cff','turn off all special text flags (default)'],
			['textspecial','b','cff','use LaTeX special text'],
			['texthidden', 'b','cff','use hidden text'],
			['textrigid',  'b','cff','set the postscript "rigid" flag'],
			'linewidth',
			['depth',      's','cs', 'set PostScript rendering depth'],
			['version',    's','cs', '(not documented in gnuplot manual)'],
			'output']},
    'ggi'    => "X or SVGAlib output via GGIlib         [NS: obsolete]",
    'gif'    => {unit=>'px',desc=>"Graphics Interchange Format (venerable but supported)",ok=>1,
		 opt=>[ qw/ transparent rounded butt linewidth dashlength font enhanced size crop /,
			['animate','l','cl',"syntax: animate=>[delay=>\$d, loop=>\$n, (no)?optimize]"],
			qw/ background output / ] },
    'excl'   => "Talaris printer support                [NS: ancient]",
    'gnugraph'=>"Gnu plotutils metalanguage output      [NS: obsolete]",
    'gpic'   => "UNIX groff(1) output                   [NS: prehistoric]",
    'gpr'    => "Apollo Graphics Primitive Resource     [NS: ancient]",
    'grass'  => {unit=>'px',desc=>"GRASS GIS file output",
		 opt=>['output']},
    'hercules'=>"PC graphics card with autodetection    [NS: obsolete]",
    'hp2623a'=> "HP 2623A terminal                      [NS: ancient]",
    'hp2648' => "HP2647 and HP2648 terminals            [NS: ancient]",
    'hp500c' => "HP500C terminal                        [NS: ancient]",
    'hpgl'   => "HPGL output (e.g. HP7475 plotter)      [NS: ancient]",
    'hpljii' => "HP Laserjet Series II                  [NS: obsolete]",
    'hppj'   => "HP PaintJet and HP3630 printers        [NS: obsolete]",
    'imagen' => "Imagen laser printers                  [NS: obsolete]",
    'jpeg'   => {unit=>"px",desc=>"JPEG image file output",ok=>1,
		 opt=>[ qw/ interlace linewidth dashlength rounded butt font enhanced size crop background output /]},
    'kyo'    => "Kyocera laserprinter native format     [NS: obsolete]",
    'latex'  => {unit=>'in',desc=>"EPS output tailored for LaTeX (see also 'epslatex')",
		 opt=>[ ['default', 'b','cff','accept whatever font is in the embedding document'],
			['courier', 'b','cff','force font to Courier'],
			['roman',   'b','cff','force font to Roman style (e.g. Times)'],
			['fontsize','s','cv', 'set font size (in points)'],  # special entry 'coz latex wants no "fontsize" keyword.
			qw/size rotate output/]},
    'linux'  =>  "Render to a Linux display dev (non-X)  [NS: obsolete]",
    'lua'    =>  "Lua script output                      [NS: obsolete]",
    'macintosh'=>"Direct rendered MacOS < 10 window      [NS: ancient]",
    'mf'     =>  "Metafont output (plot as TeX glyph)    [NS: crazy]",
    'mgr'    =>  "MGR window system                      [NS: obsolete]",
    'mif'    =>  "FrameMaker MIF format v3.0             [NS: obsolete]",
    'mp'     =>  "MetaPost metaformat for graphice       [NS: obsolete]",
    'next'   =>  "NeXT (NeXTstep) file format (RIP Jobs) [NS: ancient]",
    'openstep'=> "Openstep (NeXTStep followon)           [NS: obsolete]",
    'pbm' => {unit=>"px",desc=>"Portable BitMap format output",
	      opt=>[ ['fontsize','s','cv','font size (in pixels/points)'],
		     qw/monochrome color size output/]},
    'pdf'    => {unit=>'in',desc=>"Portable Document Format output",ok=>1,
		 opt=>[ qw/monochrome color enhanced font linewidth rounded butt solid dashed dashlength size output/ ]},
    'pdfcairo'=>{unit=>'in',desc=>"PDF output via Cairo 2-D plotting library",ok=>1,
		 opt=>[ 'enhanced',
			['monochrome','b', sub{return $_[1]?" mono ":""},
			                         "Generate a B/W plot (see 'color') if true"], # shield user from mono/monochrome
			qw/color solid dashed font linewidth rounded butt dashlength size output/ ]},
    'pm'     => "OS/2 presentation manager              [NS: ancient]",
    'png'    => {unit=>"px",desc=>"PNG image output",ok=>1,
		 opt=>[ qw/transparent interlace/,
			['truecolor','b','cf','Enable or disable true color (RGB) output'],
			qw/rounded butt linewidth dashlength tiny small medium large giant font enhanced size crop background output/]},
    'pngcairo'=>{unit=>'px',desc=>"PNG image output via Cairo 2-D plotting library",ok=>1,
		 opt=>[ 'enhanced',
			['monochrome','b',sub{return $_[1]?" mono ":""},
			                          "Generate a B/W plot (see 'color') if true"], # shield user from mono/monochrome
			qw/color solid dashed transparent crop font linewidth rounded butt dashlength size output/ ]},
    'postscript'=>{unit=>'in',desc=>"Postscript file output",ok=>1,
		   opt=>[qw/landscape portrait/,
			 ['eps',        'b','cff','Select encapsulated output (neither landscape nor portrait)'],
			 'enhanced',
			 ['simplex',    'b','cff','single sided printing'],
			 ['duplex',     'b','cff','double sided printing'],
			 ['defaultplex','b','cff','accept printer default for 1/2 sided printing'],
			 ['fontfile',   's',sub { my ($k,$v)=@_; 
						  return " $k add \"$v\" "}
			                   ,      'add font file to prologue'],
			 ['adobeglyphnames','b','cf','enable or disable Adobe style glyph names'],
			 qw/level1 leveldefault color monochrome solid dashed dashlength linewidth rounded butt clip size/,
			 ['blacktext',  'b','cff','force text to be B/W even in color plots (see "colortext")'],
			 ['colortext',  'b','cff','force text to be color even in B/W plots (see "blacktext")'],
			 'font','output']},
    'pslatex' => {unit=>'in',desc=>"Postscript file tailored for inclusion in LaTeX documents",
		  opt=>[ qw/rotate oldstyle newstyle auxfile level1 leveldefault color monochrome /,
			 qw/solid dashed dashlength linewidth rounded butt clip size fontsize output/]},
    'pstex'   => {unit=>'in',desc=>"Postscript file tailored for inclusion in raw TeX documents",
		  opt=>[ qw/rotate oldstyle newstyle auxfile level1 leveldefault color monochrome /,
			 qw/solid dashed dashlength linewidth rounded butt clip size fontsize output/]},
    'pstricks'=>"Output for pstricks.sty LaTeX macros   [NS: obsolete]",
    'qms'     =>"QMS/QUIC laser printer native format   [NS: ancient]",
    'regis'   =>"REGIS graphics language output         [NS: obsolete]",
    'rgip'    =>"RGIP metafiles                         [NS: obsolete]",
    'sun'     =>"SUNView window system window           [NS: ancient]",
    'svg'     =>{unit=>'in',desc=>"Scalable Vector Graphics (SVG) output",ok=>1,
		 opt=>[ qw/size enhanced font/,
			['fontfile','s','cq','Font file to copy into the <defs> section of the SVG'],
			qw/rounded butt solid dashed linewidth output/]},
    'svga'    =>"Output direct to a PC SVGA screen      [NS: obsolete]",
    'tek40'   =>"Tektronix 40xx plotting terminals      [NS: ancient]",
    'tek410x' =>"Tektronix 410x plotting terminals      [NS: ancient]",
    'texdraw' =>{unit=>'in',desc=>"TexDraw environment for LaTeX",
		 opt=>[ 'output' ]},
    'tgif'    =>"TGIF X11-based drawing tool            [NS: obsolete]",
    'tikz'    =>"TikZ package via Lua                   [NS: obsolete]",
    'tkcanvas'=>"Tcl/Tk canvas widget design            [NS: weird]",
    'tpic'    =>"Latex picture (use 'latex' or 'eepic') [NS: obsolete]",
    'unixpc'  =>"AT&T 3b1 and AT&T 7300 UNIX PC display [NS: ancient]",
    'unixplot'=>"UNIX plot(1) language (non-GNU version)[NS: obsolete]",
    'vgagl'   =>"Output to a VGA screen under linux     [NS: obsolete]",
    'vws'     =>"VAX Windowing System                   [NS: ancient]",
    'vx384'   =>"Vectrix 384 and Tandy color printers   [NS: ancient]",
    'windows' =>{unit=>"px",desc=>"Microsoft Windows display window",
		 opt=>[ qw/color monochrome font title size/,
			['position','l','csize','pixel location of the window'],
			'output']},
    'wxt'     =>{unit=>"px", mouse=>1,desc=>"WxWidgets display", mouse=>1,ok=>1,
		 opt=>[ qw/size enhanced font title dashed solid dashlength persist raise/,
			['ctrl',  'b','cf','enable (or disable) control-Q to quit window'],
			['close', 'b','cf','close window on completion?']
                 ]},
    'x11'     =>{unit=>"px",desc=>"X Windows display", mouse=>1,ok=>1,
		 opt=>[ 'output_',
			['title','s','cq','Window title (in title bar)'],
			qw/enhanced font linewidth solid dashed persist raise/,
			['ctrlq',  'b','cf','enable (or disable) control-Q to quit window'],
			'size']},
    'xlib'    =>"Xlib command file (for debugging X11)  [NS: useless here]"
};

##############################
# Generate the termTab from termTabSource.
#
# Each entry in termTab gets the description string and unit, and a 
# list with the same structure as the $pOpt global for parse options --
# except that the abbrevs table is not prepopulated for all devices
# (it is calculated on the fly within the constructor).
# 
# Unsupported entries are left to rot in the termTabSource structure.

$termTab = {};

for my $k(keys %$termTabSource) {
    next unless(ref($termTabSource->{$k}));   # names aren't supported -- eliminate
    my $terminalOpt = {};   #this will hold the _parseOptHash control structure we generate
    my $i = 1;              #this is a sort order counter
    
    for my $n(@{$termTabSource->{$k}->{opt}}) {
	my $name = $n;
	my $line;
	if(ref $name) {
	    $name = $n->[0];
	    $line = [@{$n}[1..3]];
	} else {
	    $line = $termTab_types->{$name} 
	       or die "Bug in parse table build! ('$name' inside terminal '$k')";
	}
	$terminalOpt->{$name} = [ $line->[0], $line->[1], undef, $i++, $line->[2]];
    }
    $terminalOpt->{"wait"} = [ 's' , sub { return "" }, undef, $i++, "wait time before throwing an error (default 5s)" ];
    $termTab->{$k} = { desc => $termTabSource->{$k}->{desc},
		       unit => $termTabSource->{$k}->{unit},
		       mouse => $termTabSource->{$k}->{mouse} // 0,
		       int   => $termTabSource->{$k}->{int} // 0,
		       opt  => [ $terminalOpt, 
				 undef, # This gets filled in on first use in the constructor.
				 "$k terminal options"
			   ]};
}

=head2 terminfo - print out information about gnuplot syntax

=for usage

    use PDL::Graphics::Gnuplot qw/terminfo/
    terminfo()
    terminfo 'aqua'

    $w = gpwin();
    $w->terminfo();

=for ref

terminfo is a reference tool to describe the Gnuplot terminal types
and the options they accept.  It's mainly useful in interactive
sessions.

=cut

sub terminfo {
    shift() if( UNIVERSAL::isa($_[0],'PDL::Graphics::Gnuplot') );

    my $terminal = shift || '';
    if((ref $terminal ? ref $terminal : $terminal) =~ m/PDL::Graphics::Gnuplot/) {
	$terminal = shift;
    }

    my $brief_form = shift;
    my $dont_print = shift;
    my $s = "";


    if($termTabSource->{$terminal}) {
	if(ref $termTabSource->{$terminal}) {
	    $s = "Gnuplot terminal '$terminal': size default unit is '$termTabSource->{$terminal}->{unit}', options are:\n";
	    my $tt = $termTab->{$terminal}->{opt}->[0];
	    for my $name(sort {$tt->{$a}->[3] <=> $tt->{$b}->[3]} keys %$tt) {
		my @info = ();
		@info = ($name, $tt->{$name}->[4]);
		$info[0] =~ s/\_$//;         #remove trailing underscore on "output_" hack
		$s .= sprintf "%10s - %s\n",@info;
	    }
	} else {
	    $s = "PDL::Graphics::Gnuplot doesn't support '$terminal'.\n$termTabSource->{$terminal}\n";
	}
	print STDERR $s unless($dont_print);
	return $s;
    }
    
    if($terminal && $terminal ne 'all'){
	$s = "terminfo: terminal '$terminal' isn't recognized.  I'm listing all supported terminals instead.\n\n";
	$terminal = '';
    }

    if(!$terminal || $terminal eq 'all') {

	if(!$terminal && !$brief_form && !$dont_print) {
	   $s .= "('terminfo \"all\"' lists all known terminals, even those not supported)\n\n";
	}

	$s .= "Gnuplot terminals supported by PDL::Graphics::Gnuplot:\n";

	$s .= "\nDISPLAY TERMINALS ([M] indicates mouse input is supported)\n";
	for my $k(sort keys %$termTab) {
	    next unless($termTab->{$k}->{int} || $termTab->{$k}->{mouse});
	    $s .= sprintf("  %10s: %s %s\n",$k,$termTab->{$k}->{mouse} ? "[M]" : "   ", $termTab->{$k}->{desc});
	}
	
	$s .= "\n\nFILE TERMINALS\n";
	for my $k(sort keys %$termTab) {
	    next if($termTab->{$k}->{int} || $termTab->{$k}->{mouse});
	    $s .= sprintf("  %10s: %s %s\n",$k,"   ", $termTab->{$k}->{desc});
	}

	if($terminal eq 'all') {
	    $s .= "\n\nThese Gnuplot terminals are not supported by PDL::Graphics::Gnuplot:\n";
	    my $i = 0;
	    for my $k(sort keys %$termTabSource) {
		next if(ref $termTabSource->{$k});
		$s .= sprintf("%12s",$k);
		$s .= "\n" unless(++$i % 6);
	    }
	    $s .= "\n";
	}
	$s .= "\nRun PDL::Graphics::Gnuplot::terminfo( \$term_name ) for information on options.\n\n";
	print STDERR $s unless($dont_print);
	return $s;
    }

}    

######################################################################
######################################################################
#####
#####  I/O to Gnuplot 
#####
#####  The following routines provide basic I/O to the underlying 
#####  Gnuplot process: starting Gnuplot, writing commands and/or data 
#####  to it, reading messages back, and ensuring synchronization.
#####
#####  Note: it is not a normal state of the object to NOT have a Gnuplot
#####  (or dump interface) running.  These are internal methods because 
#####  there is no checking elsewhere to make sure the gnuplot is there
#####  to receive commands.
#####


sub _startGnuplot
{
    ## Object code handles gnuplot in-place.
    my $this = shift;
    my $suffix = shift || "main";

    if($this->{"pid-$suffix"}) {
	_killGnuplot($this,$suffix);
    }
    
    $this->{options}->{multiplot} = 0;

    if( $this->{options}->{dump} ) {
	$this->{"in-$suffix"} = \*STDOUT;
	$this->{"pid-$suffix"} = undef; 
	$this->{dumping} = 1;
	return $this;
    } else {
	$this->{dumping} = 0;
    }

    my @gnuplot_options = $gnuplotFeatures{persist} ? qw(--persist) : ();
    
    my $in  = gensym();
    my $err = gensym();

    my $pid = open3($in,$err,$err,"gnuplot", @gnuplot_options)
	or barf "Couldn't run the 'gnuplot' backend (is gnuplot in your path?)";

    my $errSelector;
    $this->{"in-$suffix"}  = $in;
    $this->{"err-$suffix"} = $err;
    $this->{"errSelector-$suffix"} = $errSelector = IO::Select->new($err);
    $this->{"pid-$suffix"} = $pid;

    ## Find Gnuplot version and do some binary/ASCII magic.
    ## This uses the same chintzy read-one-byte-at-a-time logic as checkpoint --
    ## it's more or less cut-and-pasted from there
    my $s = "";
    our $gp_version;
    if(!$this->{dumping}) {
	print $in "show version\n";
	do {
	    if($errSelector->can_read(8) or $MS_io_braindamage) {
		my $byte;
		sysread $err, $byte, 1;
		$s .= $byte;
	    } else {
		print STDERR <<"EOM"
WARNING: Hmmm,  gnuplot didn't respond for 8 seconds.  I was expecting to read 
   a version number.  Ah, well, I'm returning the object anyway -- but don't 
   be surprised if it doesn't work.
EOM
;
		return $this;
	    }
	} until($s =~ m/Version (.*) patchlevel/i);
	
	$gp_version = $1;

	if($gp_version < $gnuplot_req_v) {
	    print STDERR <<"EOM"
WARNING: Gnuplot version ($gp_version) is earlier than recommended ($gnuplot_req_v).
Proceed with caution.  (data xfer is now ASCII by default; this will slow things
down a bit.  Images may not work.  Some plot styles may not work.)
EOM
			    ;
	    $this->{early_gnuplot} = 1;
	}
    } else {
	print STDERR <<"EOM"
WARNING: Gnuplot commands are being dumped to stdout.
EOM
;
	$this->{early_gnuplot} = 0;
    }

    _checkpoint($this, "main");

    $this;
}

sub _killGnuplot {
    my $this = shift;
    my $suffix = shift;
    my $kill_it_dead = shift;

    unless(defined($suffix)) {
	for my $k(keys %$this) {
	    next unless $k =~ m/^pid\-(.*)$/;
	    _killGnuplot($this,$1, $kill_it_dead);
	}
	return;
    }
    
    if( defined $this->{"pid-$suffix"})
    {
	my $goner = $this->{"pid-$suffix"};

	# Try Mr. Nice Guy first.
	unless($kill_it_dead) {
	    _printGnuplotPipe($this,$suffix,"exit\n");
	}

	# give it three seconds to quit nicely, then start shooting.
	local($SIG{ALRM}) = sub { kill 'HUP',$goner; };
	alarm(3);
	my $z = waitpid($goner, 0);
	alarm(0);
	
	unless($z) {
	    # give it two more seconds to die gracefully, then use the big guns.
	    local($SIG{ALRM}) = sub { kill 'KILL', $goner; };
	    alarm(2); 
	    waitpid( $goner, 0 ) ;
	    alarm(0); 
	}
	
	# This clears the status bits from the killed process, so
	# we don't report anomalous error when we finally exit.
	$? = 0;  
    }
    
    for (map { $_."-$suffix" } qw/in err errSelector pid/) {
	delete $this->{$_} if(exists $this->{$_});
    }
    $this;
}



sub _printGnuplotPipe
{
  my $this   = shift;
  my $suffix = shift;
  my $string = shift;
  my $data = shift;    # flag whether this transmission be data (0 for a command)

  # Autodetect the dump option
  # If it gets set or unset, restart gnuplot
  if(($this->{options}->{dump} && !$this->{dumping})  or  
     ($this->{dumping} && !$this->{options}->{dump})
      ) {
      $this->restart(1);

      if($this->{dumping}) {
	  print STDERR "(killed gnuplot)\n";
      } else {
	  print STDERR "(restarted gnuplot)\n";
      }
  }

  my $pipein = $this->{"in-$suffix"};

  syswrite($pipein,$string) unless($this->{dumping});

  # Mockup for half-duplex pty and pty mockups (e.g. testing Windows support)
  if($debug_echo) {
      my $k = "echobuffer-$suffix";
      $this->{$k} = "" unless(defined($this->{$k}));
      my $s = $string;
      $s =~ s/^/gnuplot> /msg unless($data);
      $this->{$k} .= $s;
  }
  
  # Various debugging options. 
  if($this->{dumping}) {
      my $ss = $string;

      # Replace non-printable ASCII characters with '?'
      $ss =~ s/[\000-\011\013-\014\016-\037\200-\377]/\?/g;
      
      if($this->{tee}) {
	  print "_printGnuplotPipe-$suffix: ".length($string)." chars: '$ss'\n";
      } elsif($this->{dumping}) {
	  print $ss;
      }
  }

  if( $this->{options}{tee} )
  {
    my $len = length $string;
    $string =~ s/[\000-\011\013-\014\016-\037\200-\377]/\?/g; 
    _logEvent($this,
              "Sent to child process (suffix $suffix) $len bytes==========\n" . $string . "\n=========================" );
  }
}

##############################
# _checkpoint -- synchronize the child and parent processes. After
# _checkpoint() returns, we know that we have read all the data from
# the child. Extra data that represents errors is returned. Warnings
# are explicitly stripped out
our $cp_serial = 0;

sub _checkpoint {
    my $this   = shift;
    my $suffix = shift || "main";
    my $opt = shift // {};
    my $notimeout = $opt->{notimeout} // 0;
    my $printwarnings = (($opt->{printwarnings} // 0) and !($this->{options}->{silent} // 0));
    
    my $pipeerr = $this->{"err-$suffix"};

    # string containing various options to this function
    my $flags = shift;
    
    # I have no way of knowing if the child process has sent its error data
    # yet. It may be that an error has already occurred, but the message hasn't
    # yet arrived. I thus print out a checkpoint message and keep reading the
    # child's STDERR pipe until I get that message back. Any errors would have
    # been printed before this
    $cp_serial++;
    my $checkpoint = "xxxxxxx Synchronizing gnuplot i/o $cp_serial xxxxxxx";
    
    _printGnuplotPipe( $this, $suffix, "\n\nprint \"$checkpoint\"\n" );
    
    
    # if no error pipe exists, we can't check for errors, so we're done. Usually
    # happens if($dump)
    return unless defined $pipeerr;
    
    my $fromerr = '';

    if( !($this->{dumping}) ) {
	_logEvent($this, "Trying to read from gnuplot (suffix $suffix)") if $this->{options}{tee};

	my $terminal =$this->{options}->{terminal};
	my $delay = (($this->{'wait'}//0) + 0) || 5;

	if($this->{"echobuffer-$suffix"}) {
	    $fromerr = $this->{"echobuffer-$suffix"};
	    $this->{"echobuffer-$suffix"} = "";
	}

	my $subproc_gone = 0 ;

	local($SIG{PIPE}) = sub { our $subproc_gone = 1; };

	do
	{ 
	    # if no data received in a few seconds, the gnuplot
	    # process is stuck. This usually happens if the gnuplot
	    # process is not in a command mode, but in a
	    # data-receiving mode. I'm careful to avoid this
	    # situation, but bugs in this module and/or in gnuplot
	    # itself can make this happen
	    #
	    # Note that the nice asynchronous part of this loop won't
	    # work on Microsoft Windows, since that OS doesn't have a
	    # working asynchronous read, and can_read doesn't work
	    # either.
	    
	    if( $MS_io_braindamage or 
		$this->{"errSelector-$suffix"}->can_read($notimeout ? undef : $delay )
		)
	    {
		my $byte;
		sysread $pipeerr, $byte, 1;
		$fromerr .= $byte;
		if($byte eq \004 or $byte eq \000 or !length($byte)) {
		    $subproc_gone = 1;
		}
	    }
	    else
	    {
		_logEvent($this, "Gnuplot $suffix read timed out") if $this->{options}{tee};
		
		$this->{"stuck-$suffix"} = 1;
		
		barf <<"EOM";
Hmmm, my $suffix Gnuplot process didn't respond for $delay seconds.
This could be a bug in PDL::Graphics::Gnuplot or gnuplot itself -- 
although for some terminals (like x11) it could be because of a 
slow network.  If you don't think it is a network problem, please
report it as a PDL::Graphics::Gnuplot bug.  You might be able to 
ignore this message, or you might have to restart() the object.
If you are getting this message spuriously, you might like to 
set the "wait" terminal option to a longer value (in seconds).
EOM
	    }
	} until ($fromerr =~ m/^$checkpoint/ms or $subproc_gone);

	if($MS_io_braindamage) {
	    # Fix newline braindamage too
	    $fromerr =~ s/\r\n/\n/g;
	}

	if($subproc_gone) {
	    _killGnuplot($this, undef, 1);
	    barf "PDL::Graphics::Gnuplot: the gnuplot process seems to have died.\n";
	}

	_logEvent($this, "Read string '$fromerr' from gnuplot $suffix process") if $this->{options}{tee};

	# Discard prompt-and-command lines up to the last prompt seen. 
	# This is necessary for MS Windows support: MS Windows doesn't have 
	# a notion of a tty versus other kind of pipe, so gnuplot always 
	# prints prompts and echoes commands.  Since there isn't much in the 
	# way of error syntax, we might miss a few errors this way.  Oh well.
	if($MS_io_braindamage) {
	    $fromerr =~ s/^[\s\r]*(gnu|multi)plot\>[^\n\r]*$//msg;
	}
	
	# Strip the checkpoint message.
	$fromerr =~ s/\s*(.*?)\s*$checkpoint.*$/$1/ms;
	
	# Replace non-printable ASCII characters with '?'
	# (preserve ^I [tab], ^J [newline], and ^M [return])
	$fromerr =~ s/[\000-\010\013-\014\016-\037\200-\377]/\?/g;

	# Find, report, and strip warnings.
	my $warningre = qr{^(?:Warning:\s*(.*?)\s*$)\n?}m;
	while( $fromerr =~ s/$warningre//gm) {
	    print STDERR "Gnuplot warning: $1\n" if( $printwarnings );
	}

	# Anything else is an error -- except on Microsoft Windows where we 
	# get additional chaff on the channel.  Try to take it out.
	if($MS_io_braindamage) {
	    $fromerr =~ s/^Terminal type set to \'[^\']*\'.*Options are \'[^\']*\'//o;
	}

	if($fromerr =~ m/^\s+\^\s*$/ms or $fromerr=~ m/^\s*line/ms) {
	    if($this->{early_gnuplot}) {
		barf "PDL::Graphics::Gnuplot: ERROR: the deprecated pre-v$gnuplot_req_v gnuplot backend issued an error:\n$fromerr\n";
	    } else {
	        barf "PDL::Graphics::Gnuplot: ERROR: the gnuplot backend issued an error:\n$fromerr\n";
	    }
	}
		       
	# strip whitespace
	$fromerr =~ s/^\s*//s;
	$fromerr =~ s/\s*$//s;
	
	return $fromerr;
    } else {
	# dumping - never generate an error.
	return "";
    }
}

sub _getGnuplotFeatures
{
  # I could use qx{} to talk to gnuplot here, but I don't want to use a
  # tty. gnuplot messes with the tty settings where it should NOT. For example
  # it turns on the local echo

  my %featureSet;

  # first, I run 'gnuplot --help' to extract all the cmdline options as features
  {
    my $in  = '';
    my $out = '';
    my $err = '';
    eval{ IPC::Run::run([qw(gnuplot --help)], \$in, \$out, \$err) };
    barf $@ if $@;

    foreach ( "$out\n$err\n" =~ /--([a-zA-Z0-9_]+)/g )
    {
      $featureSet{$_} = 1;
    }
  }

  # then I try to set a square aspect ratio for 3D to see if it works
  {
    my $in = <<EOM;
set view equal
exit
EOM
    my $out = '';
    my $err = '';


    eval{ IPC::Run::run(['gnuplot'], \$in, \$out, \$err) };
    barf $@ if $@;

    # no output if works; some output if error
    $featureSet{equal_3d} = 1 unless ($out || $err);
  }


  return %featureSet;
}

sub _logEvent
{
  my $this  = shift;
  my $event = shift;

  return unless($this->{options}->{tee}); # only log when asked.

  my $t1 = tv_interval( $this->{t0}, [gettimeofday] );
  printf STDERR "==== PDL::Graphics::Gnuplot t=%.4f: %s\n", $t1, $event;
}

1;


##############################
# Helper routine detects method call vs. function call
# syntax, and initializes the global object if necessary.
#
sub _obj_or_global {
    my $arglist = shift;
    my $this;
    if(UNIVERSAL::isa($arglist->[0],"PDL::Graphics::Gnuplot")) {
	$this = shift @$arglist;
    } else {
	unless(UNIVERSAL::isa($globalPlot,"PDL::Graphics::Gnuplot")) {
	    $globalPlot = new("PDL::Graphics::Gnuplot") ;
	}
	$globalPlot->{options}->{globalPlot} = 1;
	$this = $globalPlot;
    }
    return $this;
}

##############################
##############################
### Prefrobnicators - preprocess data before plotting, for custom plot styles
###
### Currently there is only one - used for FITS image plotting.  It's
### necessary because FITS images often have nonlinear mappings
### between pixel and scientific coordinates.

##############################
# _with_fits_prefrobnicator
#
# We support a "with fits" image style that produces output in scientific
# coordinates from a FITS file.  Ideally, we would simply produce an (x,y) grid
# that supplies scientific coordinates for each pixel -- but that doesn't work
# in the general case due to shortcomings with gnuplot itself: the three-element
# tuple form of "with image" only works for affine transformations between 
# pixel coordinates and scientific plane coordinates.
#
#  
our $fitsmap_size = 1024;
sub _with_fits_prefrobnicator {
    my( $with, $this, $chunk, @data ) = @_;
    my $resample_flag = 0;
    my @resample_dims = ($fitsmap_size,$fitsmap_size);

    # search for fits-specific 'with' options
    my $i;
    for($i=0;$i<@$with;$i++) {
	if( ($with->[$i]) =~ m/^re(s(a(m(p(l(e)?)?)?)?)?)?/i ) {
	    splice @$with, $i,1; # remove 'resample' from list
	    $resample_flag = 1;
	    if( ($with->[$i]) =~ m/(\d+)(\,(\d+))?/ ) {
		@resample_dims = ($1, $3 // $1);
		splice @$with, $i, 1;
	    }
	    $i--;
	}
    }

    eval "use PDL::Transform;";
    barf "PDL::Graphics::Gnuplot: couldn't load PDL::Transform for 'with fits' option" if($@);

    barf "PDL::Graphics::Gnuplot: 'with fits' special option requires a single FITS image\n" if(@data != 1);
    my $data = $data[0];
    
    my $h = $data->gethdr();
    unless($h   and   ref $h eq 'HASH'   and   $h->{NAXIS}   and   $h->{NAXIS1}   and   $h->{NAXIS2}) {
	if($data->ndims==2 or ($data->ndims==3 && ($data->dim(3)==3 || $data->dim(3)==1))) {
	    warn("PDL::Graphics::Gnuplot: 'with fits' expected a FITS header.  Using pixel coordinates...\n");
		 $h = {
		     NAXIS=>2,
		     NAXIS1 => $data->dim(0), 
		     NAXIS2 => $data->dim(1),
		     CRPIX1=>1,		         CRPIX2=>1,
		     CRVAL1=>0,   		 CRVAL2=>0,
		     CDELT1=>1,                  CDELT2=>1,
		     CTYPE1=>"X",                CTYPE2=>"Y",
		     CUNIT1=>"Pixels",           CUNIT2=>"Pixels"
		 }
	} else {
	    barf("PDL::Graphics::Gnuplot: 'with fits' got a (non-image) ".join("x",$data->dims)." PDL with no FITS header.\n");
	}
    }

    ##############################
    # Now find the dataspace boundaries for the map, so we don't waste pixels.
    my ($xmin,$xmax,$ymin,$ymax);
    if(exists($this->{options}->{xrange})) {
	$xmin = $this->{options}->{xrange}->[0];
	$xmax = $this->{options}->{xrange}->[1];
    }
    if(exists($this->{options}->{yrange})) {
	$ymin = $this->{options}->{yrange}->[0];
	$ymax = $this->{options}->{yrange}->[1];
    }

    unless(defined($xmin) && defined($xmax) && defined($ymin) && defined($ymax)) {
	my $pix_corners = pdl([0,0],[0,1],[1,0],[1,1]) * pdl($data->dim(0),$data->dim(1)) - 0.5;
	my $corners = $pix_corners->apply(t_fits($data));

	$xmin = $corners->slice("(0)")->min unless defined($xmin);
	$xmax = $corners->slice("(0)")->max unless defined($xmax);
	$ymin = $corners->slice("(1)")->min unless defined($ymin);
	$ymax = $corners->slice("(1)")->max unless defined($ymax);
    }

    if($ymin > $ymax) {
	my $a = $ymin; $ymin = $ymax; $ymax = $a;
    }
    if($xmin > $xmax) {
	my $a = $xmin; $xmin = $xmax; $xmax = $a;
    }
    
    our $dest_hdr = {NAXIS=>2,
		    NAXIS1=> $resample_dims[0],     NAXIS2=>$resample_dims[1],
		    CRPIX1=> 0.5,                   CRPIX2=>0.5,
		    CRVAL1=> $xmin,                 CRVAL2=>$ymin,
		    CDELT1=> ($xmax-$xmin)/($resample_dims[0]),
		    CDELT2=> ($ymax-$ymin)/($resample_dims[1]),
		    CTYPE1=> $h->{CTYPE1},	    CTYPE2=> $h->{CTYPE2},
		    CUNIT1=> $h->{CUNIT1},          CUNIT2=> $h->{CUNIT2}
    };

    my ($d2,$ndc);
    if($resample_flag) {
	my $d1 = double $data;
	unless($data->hdrcpy) {$d1->sethdr($data->gethdr);} # no copying - ephemeral value
	$d2 = $d1->map( t_identity(), $dest_hdr,{method=>'h'} );  # Rescale into coordinates proportional to the scientific ones
	$ndc = ndcoords($d2->dim(0),$d2->dim(1)) -> apply( t_fits($d2) );
    } else {
	$d2 = $data;
	$ndc = ndcoords($data->dim(0),$data->dim(1))->apply(t_fits($data));
    }

    # Now update plot options to set the axis labels, if they haven't been updated already...
    unless(defined $this->{options}->{xlabel}) {
	$this->{tmp_options}->{xlabel} = [join(" ",
					  $h->{CTYPE1} || "X",
					  $h->{CUNIT1} ? "($h->{CUNIT1})" : "(pixels)"
				      )];
    }
    unless(defined $this->{options}->{ylabel}) {
	$this->{tmp_options}->{ylabel} = [join(" ",
					  $h->{CTYPE2} || "Y",
					  $h->{CUNIT2} ? "($h->{CUNIT2})" : "(pixels)"
				      )];
    }
    unless(defined $this->{options}->{cblabel}) {
	$this->{tmp_options}->{cblabel} = [join(" ",
					    $h->{BTYPE} || "Value",
					    $h->{BUNIT} ? "($h->{BUNIT})" : ""
				       )];
    }

    if($d2->ndims == 2) {
	$with->[0] = 'image';
	$chunk->{options}->{with} = [@$with];
	return ($ndc->mv(0,-1)->dog, $d2);
    }

    if($data->ndims == 3 and $data->dim(2)==3) {
	$with->[0] = 'rgbimage';
	return ($ndc->mv(0,-1)->dog, $d2->dog);
    }

    if($data->ndims == 3 and $data->dim(2)==4) {
	$with->[0] = 'rgbalpha';
	return ($ndc->mv(0,-1)->dog, $d2->dog);
    }

    barf "PDL::Graphics::Gnuplot: 'with fits' needs an image, RGB triplet, or RGBA quad\n";

}


=head1 COMPATIBILITY

Everything should work on all platforms that support Gnuplot and Perl.
Currently, only MacOS, Fedora Linux, and Debian Linux have been tested
to work.  Please report successes or failures on other platforms to
the authors. A transcript of a failed run with {tee => 1} would be most
helpful.

=head1 REPOSITORY

L<https://github.com/drzowie/PDL-Graphics-Gnuplot>

=head1 AUTHOR

Dima Kogan, C<< <dima@secretsauce.net> >> and Craig DeForest, C<< <craig@deforest.org> >>

=head1 STILL TO DO

=over 3

=item some plot and curve options need better parsing:

=over 3

=item - options to "with" selection: accept a list ref instead of a string with args

=item - labels need attention (plot option labels)

They need to be handled as hashes, not just as array refs.  Also, they don't seem to be working with timestamps.
Further, deeply nested options (e.g. "at" for labels) need attention.

=back

=item - new plot styles

The "boxplot" plot style (new to 4.6?) requires a different using syntax and will require some hacking to support.

=item - ephemeral state isn't.

Ephemeral plot options leave state behind in the underlying gnuplot process.  Following each plot with a reset() 
doesn't do what you really want.  Start each plot with a reset()?  Hold default values in the parse table?

=back

=head1 RELEASE NOTES

=head2 v1.1

- Handles communication with command echo on the pipe (for Microsoft Windows)

- Better gnuplot error reporting

- Fixed date range handling

=head2 v1.2

- Handles communication better on Microsoft Windows (MSW has brain damage).

- Improvements in documentation

- Handles PDF output in scripts

- Handles 2-D and 1-D columns in 3-D plots (grid vs. threaded lines)


=head1 LICENSE AND COPYRIGHT

Copyright 2011,2012 Dima Kogan and Craig DeForest

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Perl Artistic License included with
the Perl language.

See http://dev.perl.org/licenses/ for more information.

=cut

