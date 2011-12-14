=head1 NAME

PDL::Graphics::Gnuplot - Gnuplot-based plotting for PDL

=head1 SYNOPSIS

 pdl> use PDL::Graphics::Gnuplot;

 pdl> $x = sequence(101) - 50;
 pdl> gplot($x**2);

 pdl> gplot( {title => 'Parabola with error bars'},
       with => 'xyerrorbars', legend => 'Parabola',
       $x**2 * 10, abs($x)/10, abs($x)*5 );

 pdl> $xy = zeros(21,21)->ndcoords - pdl(10,10);
 pdl> $z = inner($xy, $xy);
 pdl> gplot({title  => 'Heat map', '3d' => 1,
        extracmds => 'set view 0,0'},
        with => 'image', $z*2);

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

PDL::Graphics::Gnuplot also implements an object oriented
interface. Plot objects track individual gnuplot subprocesses.  Direct
calls to C<gplot()> are tracked through a global object that stores
globally set configuration variables.

Gnuplot collects two kinds of options hash: plot options, which
describe the overall structure of the plot being produced (e.g. axis
specifications, window size, and title), from curve options, which
describe the behavior of individual traces or collections of points
being plotted.  In addition, the module itself supports options that
allow direct pass-through of plotting commands to the underlying
gnuplot process.

=head2 Basic plotting

Gnuplot generates many kinds of plot, from basic line plots and histograms
to scaled labels.  Individual plots can be 2-D or 3-D, and different sets 
of plot styles are supported in each mode.  Plots can be sent to a variety
of devices; see the description of plot options, below.

You select a plot style with the "with" curve option, as in

 $x = xvals(51)-25; $y = $x**2;
 gplot(with=>'points', $x, $y);  # Draw points on a parabola
 gplot(with=>'lines', $x, $y);   # Draw a parabola
 gplot({title=>"Parabolic fit"},
       with=>"yerrorbars", legend=>"data", $x, $y+(random($y)-0.5)*2*$y/20, pdl($y/20),
       with=>"lines",      legend=>"fit",  $x, $y);

Normal threading rules apply across the arguments to a given plot.

At least the first data column in a tuple is required to be a PDL.
Subsequent data columns can be delivered as string data if desired, in a
Perl list ref.  If you use a list ref as a data column, then normal
threading is disabled and all arguments must be 1-D and contain the 
same number of elements.  For example:

 $x = xvals(5);
 $y = xvals(5)**2;
 $labels = ['one','two','three','four','five'];
 gplot(with=>'labels',$x,$y,$labels);

See below for supported plot styles.

=head2 Options arguments

The plot options are parameters that affect the whole plot, like the title of
the plot, the axis labels, the extents, 2d/3d selection, etc. All the plot
options are described below in L</"Plot options">.

The curve options are parameters that affect only one curve in particular. Each
call to C<plot()> can contain many curves, and options for a particular curve
I<precede> the data for that curve in the argument list. Furthermore, I<curve
options are all cumulative>. So if you set a particular style for a curve, this
style will persist for all the following curves, until this style is turned
off. The only exception to this is the C<legend> option, since it's very rarely
a good idea to have multiple curves with the same label. An example:

 gplot( with => 'points', $x, $a,
        y2   => 1,        $x, $b,
        with => 'lines',  $x, $c );

This plots 3 curves: $a vs. $x plotted with points on the main y-axis (this is
the default), $b vs. $x plotted with points on the secondary y axis, and $c
vs. $x plotted with lines also on the secondary y axis. All the curve options
are described below in L</"Curve options">.

=head2 Data arguments

Following the curve options in the C<plot()> argument list is the actual data
being plotted. Each output data point is a "tuple" whose size varies depending on
what is being plotted. For example if we're making a simple 2D x-y plot, each
tuple has 2 values; if we're making a 3d plot with each point having variable
size and color, each tuple has 5 values (x,y,z,size,color). Each tuple element 
must be passed separately.  For ordinary (non-curve) plots, the 0 dim of the 
tuple elements runs across plotted point.  PDL threading is active, so multiple 
curves with similar curve options can be plotted by stacking data inside the 
passed-in piddles.  

An example:

 my $pi    = 3.14159;
 my $theta = xvals(201) * 6 * $pi / 200;
 my $z     = xvals(201) * 5 / 200;

 plot( {'3d' => 1, title => 'double helix'},
       { with => 'linespoints pointsize variable pointtype 2 palette',
         legend => ['spiral 1','spiral 2'] },
         pdl( cos($theta), -cos($theta) ),       # x
         pdl( sin($theta), -sin($theta) ),       # y
         $z,                                     # z
         (0.5 + abs(cos($theta))),               # pointsize
         sin($theta/3)                           # color
    );

This is a 3d plot with variable size and color. There are 5 values in the tuple,
which we specify. The first 2 piddles have dimensions (N,2); all the other
piddles have a single dimension. Thus the PDL threading generates 2 distinct
curves, with varying values for x,y and identical values for everything else. To
label the curves differently, 2 different sets of curve options are given. Since
the curve options are cumulative, the style and tuplesize needs only to be
passed in for the first curve; the second curve inherits those options.

=head3 Implicit domains

When making a simple 2D plot, if exactly 1 dimension is missing,
PDL::Graphics::Gnuplot will use C<sequence(N)> as the domain. This is why code
like C<plot(pdl(1,5,3,4,4) )> works. Only one piddle is given here, but a
default tuplesize of 2 is active, and we are thus exactly 1 piddle short. This
is thus equivalent to C<plot( sequence(5), pdl(1,5,3,4,4) )>.

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

One thing to watch out for it to make sure PDL::Graphics::Gnuplot doesn't get
confused about when to use implicit domains. For example, C<plot($a,$b)> is
interpreted as plotting $b vs $a, I<not> $a vs an implicit domain and $b vs an
implicit domain. If 2 implicit plots are desired, add a separator:
C<plot($a,{},$b)>. Here C<{}> is an empty curve options hash. If C<$a> and C<$b>
have the same dimensions, one can also do C<plot($a-E<gt>cat($b))>, taking advantage
of PDL threading.

=head2 Images

PDL::Graphics::Gnuplot supports image plotting in three styles via the "with"
curve option. 

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
 image( with=>'image', $rgbim ); # display an RGB image (longer form)

Some additional plot styles exist to specify RGB and RGB transparent forms
directly.  These are the "with" styles "rgbimage" and "rgbalpha".  For each
of them you must specify the channels as separate PDLs:

 plot( with=>'rgbimage', $rgbim->dog );           # RGB  the long way
 plot( with=>'rgbalpha', $rgbim->dog, ($im>0) );  # RGBA the long way 

According to the gnuplot specification you can also give X and Y
values for each pixel, as in

 plot( with=>'image', xvals($im), yvals($im), $im )

but this appears not to work properly for anything more complicated
than a trivial matrix of X and Y values.

=head2 Interactivity

The graphical backends of Gnuplot are interactive, allowing the user
to pan, zoom, rotate and measure the data in the plot window. See the
Gnuplot documentation for details about how to do this. Some terminals
(such as wxt) are persistently interactive, and the rest of this
section does not apply to them. Other terminals (such as x11) maintain
their interactivity only while the underlying gnuplot process is
active -- i.e. until another plot is created with the same PDL::Graphics::Gnuplot
object, or until the perl process exits (whichever comes first).

=head1 PLOT OPTIONS

Gnuplot controls plot style with "plot options" that configure and
specify virtually all aspects of the plot to be produced.   Plot
options are tracked as stored state in the PDL::Graphics::Gnuplot
object.  You can set them by passing them in to the constructor, to an
C<options> method, or to the C<plot> method itself.

Nearly all the underlying Gnuplot plot options are supported, as well
as some additional options that are parsed by the module itself for
convenience.

=head2 Output: terminal, termoption, output, device, hardcopy

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


=head2 Titles: title, (x|x2|y|y2|z|cb)label, key

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

=item ( on | off ) - turn the key on or off

=item ( inside | outside | lmargin | rmargin | tmargin | bmargin | at <pos> )

These keywords set the location of the key -- "inside/outside" is
relative to the plot border; the margin keywords indicate location in
the margins of the plot; and at <pos> (where <pos> is a 2-list
containing (x,y): C<key=>[at=>[0.5,0.5]]>) is an exact location to place the key.

=item ( left | right | center ) ( top | bottom | center ) - horiz./vert. alignment

=item ( vertical | horizontal ) - stacking direction within the key

=item ( Left | Right ) - justification of plot labels within the key (note case)

=item [no]reverse - switch order of label and sample line

=item [no]invert - invert the stack order of the labels

=item samplen <length> - set the length of the sample lines

=item spacing <dist> - set the spacing between adjacent labels in the list

=item [no]autotitle - control whether labels are generated when not specified

=item title "<text>" - set a title for the key

=item [no]enhanced - override terminal settings for enhanced text interpretation

=item font "<face>,<size>" - set font for the labels

=item textcolor <colorspec> 

=item [no]box linestyle <ls> linetype <lt> linewidth <lw> - control box around the key

=back

=head2 axis, grid, and border control: grid, (x|x2|y|y2|z)zeroaxis, border

Normally, tick marks and labels are applied to the border of a plot,
and no extra axes (e.g. the y=0 line) nor coordinate grids are shown.  You can
specify which (if any) zero axes should be drawn, and which (if any)
borders should be drawn.

The C<border> option controls whether the plot itself has a border
drawn around it.  You can feed it a scalar boolean value to indicate
whether borders should be drawn around the plot -- or you can feed in a list
ref containing options.  The options are all optional but must be supplied
in the order given.

=over 3

=item <integer> - packed bit flags for which border lines to draw

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

=item ( back | front ) - draw borders first or last (controls hidden line appearance)

=item linewidth <lw>, linestyle <ls>, linetype <lt> 

These are Gnuplot's usual three options for line control.

=back

To draw each axis set the appropriate "zeroaxis" parameter -- i.e. to draw
the X axis (y=0), use C<xzeroaxis=>1>.  If you just want the axis
turned on with default values, you can feed in a Boolean scalar; if
you want to set its parameters, you can feed in a list ref containing
linewidth, linestyle, and linetype (with appropriate parameters for each), e.g.
C<xzeroaxis=>[linewidth=>2]>.

To draw a coordinate grid with default values, set C<grid=>1>.  For more 
control, feed in a list ref with zero or more of the following parameters, in order:

=over 3

=item tics specifications

These keywords indicate whether gridlines should be drawn on axis tics (see below) for each axis.  Each one takes the form of either "no" or "m" or "", followed by an axis name and "tics" -- e.g. C<grid=>["noxtics","ymtics"]> draws no X gridlines and draws (horizontal) Y gridlines on Y axis major and minor tics, while C<grid=>["xtics","ytics"]> or C<grid=>["xtics ytics"]> will draw both vertical (X) and horizontal (Y) grid lines on major tics.

=head2 Axis ranging and mode: (x|x2|y|y2|z|r|cb|t|u|v)range, autoscale, logscale

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
of the logarithm: C<logscale=>[xy=>10]>.  You can also leave off the
base if you want base-10 logs: C<logscale=>['xy']>.

=head2 Axis tick marks - [m](x|x2|y|y2|z|cb)tics

Label tick marks are called "tics" within Gnuplot, and they are extensively
controllable via the "<axis>tics" options.  In particular, major and minor
ticks are supported, as are arbitrarily variable length ticks, non-equally
spaced ticks, and arbitrarily labelled ticks.  Support exists for time formatted
ticks (see "Time data" below).

By default, gnuplot will automatically place major and minor ticks.
You can turn off ticks on an axis by setting the appropriate <foo>tics
option to a defined, false scalar value (e.g. C<xtics=>0>), and turn them
on with default values by setting the option to a true scalar value
(e.g. C<xtics=>1>). 

If you prepend an 'm' to any tics option, it affects minor tics instead of
major tics (major tics typically show units; minor tics typically show fractions
of a unit).

Each tics option can accept a list ref containing options to pass
directly to Gnuplot (they are not parsed further -- though a future
version of PDL::Graphics::Gnuplot may accept a hash ref and parse it
into an options string).  You can interpolate all the words into a
single string, provided it is contained in a list ref.  The keywords
are all optional, but must appear in the order given here, and may not
be abbreviated.  They are:

=over 2

=item * ( axis | border ) - are tics on the axis, or on the plot border?

=item * ( nomirror | mirror ) - place mirrored tics on the opposite axis/border?

=item * ( in | out ) - controls tic direction relative to the plot

=item * scale ( default | <major>[,<minor>] ) - multiplier on tic length

=item * ( norotate | rotate [by <ang>] ) - turn label text by 90deg or specified angle

=item * ( nooffset | offset <x>,<y>[,<z>] ) - offset label text from default position

=item * (autofreq | <incr> | <start>,<incr>[,<end>] | <label-list>) - set tic locations

=item * format "<formatstring>" - printf-style formatting for tic labels

=item * font "<font>[,<size>]" - set font name and size (system font name)

=item * rangelimited - limit tics to the range of values actually present in the plot

=item * textcolor <colorspec> - set the color of the ticks (see "color specs" below)

=back

For example, to turn on inward mirrored X axis ticks with diagonal Arial 9 text, use:

 xtics => ['axis','mirror','in','rotate by 45','font "Arial,9"']

=head2 Time/date values - (x|x2|y|y2|z|cb)(m|d)tics, (x|x2|y|y2|z|cb)data

Gnuplot contains support for plotting time, date, or elapsed time on
any of its axes.  There are three main methods, which are mutually exclusive
(i.e. you should not attempt to use two at once on the same axis).

=over 3

=item B<Plotting timestamps using UNIX times>

You can set any axis to plot timestamps rather than numeric values by
setting the corresponding "data" plot option to "time",
e.g. C<xdata=>"time">.  If you do so, then numeric values in the
corresponding data are interpreted as UNIX times (seconds since the
UNIX epoch).  No provision is made for UTC->TAI conversion (yet).  You
can format how the times are plotted with the "format" option in the
various "tics" options(above).  Output specifiers should be in
UNIX strftime(3) format -- for example, 
 
 xdata=>"time",xtics=>['format "%G-%m-%dT%H:%M:%S"']

will plot UNIX times as ISO timestamps in the ordinate.

=item B<day-of-week plotting>

If you just want to plot named days of the week, you can instead use 
the dtics options set plotting to day of week, where 0 is Sunday and 6
is Saturday; values are interpreted modulo 7.  For example,
C<xmtics=>1,xrange=>[-4,9]> will plot two weeks from Wednesday to
Wednesday.

=item B<month-of-year plotting>

The mtics options set plotting to months of the year, where 1 is January and 12 is 
December, so C<xdtics=>1, xrange=>[0,4]> will include Christmas through Easter.

=back

=head2 Plot location and size - (t|b|l|r)margin, offsets, origin, size, justify, clip

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
ratios, as in C<size=>[$xfrac, $yfrac]>.  You can also feed in some keywords
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
independently by passing in booleans with their names: C<clip=>[points=>1,two=>0]>.

=head2 Color: colorbox, palette, clut

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
e.g. "clut=>'xxx'".  (This should be improved in a future version).

=head2 3-D: trid, view, pm3d, hidden3d, dgrid3d, surface, xyplane, mapping

If C<trid> or its synonym C<3d> is true, Gnuplot renders a 3-D plot.
This changes the default tuple size from 2 to 3.  This
option is used to switch between the Gnuplot "plot" and "splot"
command, but it is tracked with persistent state just as any other
option.

The C<view> option controls the viewpoint of the 3-D plot.  It takes a
list of numbers: C<view=>[$rot_x, $rot_z, $scale, $scale_z]>.  After
each number, you can omit the subsequent ones.  Alternatively,
C<view=>['map']> represents the drawing as a map (e.g. for contour
plots) and C<view=>[equal=>'xy']> forces equal length scales on the X
and Y axes regardless of perspective, while C<view=>[equal=>'xyz']>
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
"relative", and a number.  C<xyplane=>[at=>$z]> places the XY plane at the
stated Z value (in scientific units) on the plot.  C<xyplane=>[relative=>$frac]>
places the XY plane $frac times the length of the scaled Z axis *below* the Z 
axis (i.e. 0 places it at the bottom of the plotted Z axis; and -1 places it 
at the top of the plotted Z axis).

C<mapping> takes a single string: "cartesian", "spherical", or
"cylindrical".  It determines the interpretation of data coordinates
in 3-space. (Compare to the C<polar> option in 2-D).

=head2 Contour plots - contour, cntrparam

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

=head2 Polar plots - polar, angles, mapping

You can make 2-D polar plots by setting C<polar> to a true value.  The 
ordinate is then plotted as angle, and the abscissa is radius on the plot.
The ordinate can be in either radians or degrees, depending on the 
C<angles> parameter

C<angles> takes either "degrees" or "radians" (default is radians).

C<mapping> is used to set 3-D polar plots, either cylindrical or spherical 
(see the section on 3-D plotting, above).

=head2 Markup - label, arrow, object

You specify plot markup in advance of the plot command, with plot
options.  The options give you access to a collection of (separately)
numbered descriptions that are accumulated into the plot object.  To
add a markup object to the next plot, supply the appropriate options
as a list ref or as a single string.  To specify all markup objects
at once, supply the appropriate options for all of them as a nested 
list-of-lists.

To modify an object, you can specify it by number, either by appending
the number to the plot option name (e.g. C<arrow3>) or by supplying it
as the first element of the option list for that object.  

To remove all objects of a given type, supply undef (e.g. C<arrow=>undef>).

For example, to place two labels, use the plot option:

 label => [["Upper left",at=>"10,10"],["lower right",at=>"20,5"]];

To add a label to an existing plot object, if you don't care about what
index number it gets, do this:

 $w->options( label=>["my new label",at=>"10,20"] );

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
a comma, as in C<label2=>["foo",at=>"5,3">, to specify (X,Y) location 
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

 C<label3=>["foo",at=>"3,4",font=>'"Helvetica,18"']>.

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
a comma, as in C<label2=>["foo",at=>"5,3">, to specify (X,Y) location 
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

You can specify a rectangle with C<from=>$pos1, [r]to=>$pos2>, with C<center=>$pos1, size=>"$w,$h">,
or with C<at=>$pos1,size=>"$w,$h">.

You can specify an ellipse with C<at=>$pos, size=>"$w,$h"> or C<center=>$pos size=>"$w,$h">, followed
by C<angle=>$a>.

You can specify a circle with C<at=>$pos, size=>"$w,$h"> or C<center=>$pos size=>"$w,$h">, followed 
by C<size=>$radius> and (optionally) C<arc=>"[$begin:$end]">.

You can specify a polygon with C<from=>$pos1,to=>$pos2,to=>$pos3,...to=>$posn> or with 
C<from=>$pos1,rto=>$diff1,rto=>$diff2,...rto=>$diffn>.

=item ( front | back | behind ) - draw the object last | first | really-first.

=item fc <colorspec> - specify fill color

=item fs <fillstyle> - specify fill style

=item lw <width> - multiplier on line width

=back

=head2 Appearance tweaks - bars, boxwidth, isosamples, pointsize, style

TBD - more to come.

=head2 Locale/internationalization - locale, decimalsign

C<locale> is used to control date stamp creation.  See the gnuplot manual.

C<decimalsign>  accepts a character to use in lieu of a "." for the decimalsign.
(e.g. in European countries use C<decimalsign=>','>).

=head2 Miscellany: globalwith, timestamp, zero, fontpath

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
C<binary=>0> option.

C<dump> is used for debugging. If true, it writes out the gnuplot commands to STDOUT
I<instead> of writing to a gnuplot process. Useful to see what commands would be
sent to gnuplot. This is a dry run. Note that this dump will contain binary
data, if the 'binary' option is given (see below)

=item log

Used for debugging. If true, writes out the gnuplot commands to STDERR I<in
addition> to writing to a gnuplot process. This is I<not> a dry run: data is
sent to gnuplot I<and> to the log. Useful for debugging I/O issues. Note that
this log will contain binary data, if the 'binary' option is given (see below)

=back

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

=item y2

If true, requests that this curve be plotted on the y2 axis instead of the main y axis

=item tuplesize

Specifies how many values represent each data point. For 2D plots this defaults
to 2; for 3D plots this defaults to 3.

=back

=head1 PLOT STYLES



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

  plot(with => 'yerrorbars', tuplesize => 3,
       $y, $y->ones);

Same with an explicit $x domain:

  plot(with => 'yerrorbars', tuplesize => 3,
       $x, $y, $y->ones);

Symmetric errorbars on both x and y. $x +- 1, $y +- 2:

  plot(with => 'xyerrorbars', tuplesize => 4,
       $x, $y, $x->ones, 2*$y->ones);

To plot asymmetric errorbars that show the range $y-1 to $y+2 (note that here
you must specify the actual errorbar-end positions, NOT just their deviations
from the center; this is how Gnuplot does it)

  plot(with => 'yerrorbars', tuplesize => 4,
       $y, $y - $y->ones, $y + 2*$y->ones);

=head3 More multi-value styles

In Gnuplot 4.4.0, these generally only work in ASCII mode. This is a bug in
Gnuplot that will hopefully get resolved.

Plotting with variable-size circles (size given in plot units, requires Gnuplot >= 4.4)

  plot(with => 'circles', tuplesize => 3,
       $x, $y, $radii);

Plotting with an variably-sized arbitrary point type (size given in multiples of
the "default" point size)

  plot(with => 'points pointtype 7 pointsize variable', tuplesize => 3,
       $x, $y, $sizes);

Color-coded points

  plot(with => 'points palette', tuplesize => 3,
       $x, $y, $colors);

Variable-size AND color-coded circles. A Gnuplot (4.4.0) bug make it necessary to
specify the color range here

  plot(cbmin => $mincolor, cbmax => $maxcolor,
       with => 'circles palette', tuplesize => 4,
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

         { with => 'pointslines pointsize variable pointtype 7 palette', tuplesize => 5,
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

The C<hardcopy> option is a shorthand for the C<terminal> and C<output>
options. If more control is desired, the latter can be used. For example to
generate a PDF of a particular size with a particular font size for the text,
one can do

  plot(terminal => 'pdfcairo solid color font ",10" size 11in,8.5in',
       output   => 'output.pdf',
       $x, $y);

This command is equivalent to the C<hardcopy> shorthand used previously, but the
fonts and sizes can be changed.


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

our $VERSION = '0.11ced';

use base 'Exporter';
our @EXPORT_OK = qw(plot plot3d line lines points image terminfo);
our @EXPORT = qw(gpwin gplot);


our $check_syntax = 0;


# when testing plots with ASCII i/o, this is the unit of test data
my $testdataunit_ascii = "10 ";       # for ascii I/O - not around any more...
my $testdataunit_binary = "........"; # 8 bytes - length of a double

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
#
# DESTROY - destructor kills gnuplot task
#
# _startGnuplot - helper for new


=head2 gpwin - exported constructor (synonymous with new)

=for usage

 use PDL::Graphics::Gnuplot;
 $w = gpwin( $options );
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

    $w = new PDL::Graphics::Gnuplot( device, %device_options, {plot_options} );
    $w->plot( @plot_args );

=for ref

Creates a PDL::Graphics::Gnuplot object to make a persistent plot.

=for example

  my $plot = PDL::Graphics::Gnuplot->new({title => 'Object-oriented plot'});
  $plot->plot( legend => 'curve', sequence(5) );

The plot options can be passed into the constructor as a trailing hash
ref; the curve options and the data are passed into the method. One
advantage of making plots this way is that there's a gnuplot process
associated with each PDL::Graphics::Gnuplot instance, so as long as
C<$plot> exists, the plot will be interactive. Also, calling
C<$plot-E<gt>plot()> multiple times reuses the plot window instead of
creating a new one.

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

our $termTab;

sub new
{
  my $classname = shift;
  
  # Check that, if there is at least one more option, it is recognizable as a terminal
  my $terminal;

  our $termTabSource;

  if(@_) {
      $terminal = lc shift;
      if(!exists($termTab->{$terminal})) {
	  my $s = "PDL::Graphics::Gnuplot::new: the first argument to new must be a terminal type.\n".
	      "Run \"PDL::Graphics::Gnuplot::terminfo\" for a list of valid terminal types.\n";
	  barf($s);
      }
      
      # Generate abbrevs on first invokation for each terminal type.
      unless($termTab->{$terminal}->{opt}->[1]) {
	  $termTab->{$terminal}->{opt}->[1] = _gen_abbrev_list(keys %{$termTab->{$terminal}->{opt}[0]});
	  $termTab->{$terminal}->{opt}->[0]->{__unit__} = ['s','-']; # Hack so we can stash the unit string in there later.
      }
  }

  # Check if the last passed-in parameter is a hash ref -- if it is, then it is plot options
  my $poh;
  if( (0+@_) && ref($_[$#_]) eq 'HASH') {
      $poh = pop @_;
  }

  # Declare & bless minimal object to hold everything.
  my $this = { t0          => [gettimeofday],   # last access
	       options     => {multiplot=>0},   # multiplot option actually holds multiplotting state flag
	       replottable => 0,                # small amount of state...
              };
  bless($this,$classname);

  # parse plot options
  if($poh) {
      options($this,$poh);
  }

  my $termOptions = {};
  my $outputString;


  # parse "terminal" options
  if($terminal) {
      if($termTab->{$terminal} && $termTab->{$terminal}->{opt}) {

	  # Stuff the default size unit into the options hash, so that the parser has access to it.
	  $termOptions->{'__unit__'} = $termTab->{$terminal}->{unit};

	  _parseOptHash( $termOptions, $termTab->{$terminal}->{opt}, @_ );

	  $this->{options}->{output} = $termOptions->{output};
	  delete $termOptions->{output};

	  ## Emit the terminal options line for this terminal.
	  $this->{options}->{terminal} = join(" ", ($terminal, _emitOpts( $termOptions, $termTab->{$terminal}->{opt} )));


	  
      } else {
	  barf "PDL::Graphics::Gnuplot doesn't yet support this device, sorry\n";
      }
  }

  
  # now that options are parsed, start up a gnuplot
  # and copy the keys into the object
  _startGnuplot($this,'main');
  _startGnuplot($this,'syntax') if($check_syntax);

  _logEvent($this, "startGnuplot() finished"); 

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
    return $me->{options};
}

=head2 restart - restart the gnuplot backend for a plot object

=for usage

    $w->restart();
    PDL::Graphics::Gnuplot::restart();

=for ref

Occasionally the gnuplot backend can get into an unknown state.  
C<reset> kills the gnuplot backend and starts a new one, preserving
options state in the object.  

Called with no arguments, C<restart> applies to the global plot object.

=cut

# reset - tops and restarts the underlying gnuplot process for an object
sub restart {
    my $this = _obj_or_global(\@_);
    _killGnuplot($this);
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
options except "terminal" and "output" are cleared.  This is similar to 
the "reset" command supported by gnuplot itself.  


=cut

sub reset {
    my $this = _obj_or_global(\@_);
     for my $k(keys %{$this->{options}}) {
	unless ( $k =~ m/(terminal|output)/ ) {
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
    
    return $this;
}

######################################################################
######################################################################
#
# plot - the main API function to generate a plot. 

=head2 gplot - exported plot method (synonym for "PDL::Graphics::Gnuplot::plot")

=head2 plot - method to generate a plot

=for ref

The main plotting routine in PDL::Graphics::Gnuplot.

By default, each C<gplot()> call creates a new plot in a new window.

=for usage

 gplot({temp_plot_options},                 # optional
      curve_options, data, data, ... ,      # curve_options are optional for the first plot
      curve_options, data, data, ... );

Most of the arguments are optional.

=for example

 use PDL::Graphics::Gnuplot qw(plot);
 my $x = sequence(101) - 50;
 plot($x**2);

See main POD for PDL::Graphics::Gnuplot for details.

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
    my $o;
    if( (ref $_[0]) =~ /^(HASH|ARRAY)/) {
	my $first_arg = shift;
	$o = dclone($this->{options});
	eval { _parseOptHash( $o, $pOpt, $first_arg ); };
	
	if($@ =~ m/^No /) {
	    # Found an unrecognized keyword -- put the ref back, clear the error, and keep going.
	    unshift (@_,$first_arg);
	    $@ = "";
	    $o = $this->{options}
	} elsif($@) {
	    # Some other actual exception -- pass it down the line.
	    barf $@ . "   (while parsing presumed extra plot options at start of plot command)\n";
	}
    } else {
	# First arg isn't a hash or array ref
	$o = $this->{options};
    }
    local($this->{options}) = $o;

    # Make sure to reset the palette to the gnuplot default if it's not set here
    $this->{options}->{palette} = [] unless($this->{options}->{palette});

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
    # Zeroth: fix up some of the option defaults based on context.  In particular, gnuplot 4.4 
    # doesn't handle image scaling anything like correctly, so unless an xrange/yrange is specified
    # we have to take care of it ourselves.  
    
    # Check binary mode operation.  We normally do everything in binary, but 
    # if certain bug-triggering conditions are identified we can default to ASCII.
    # 
    # Currently, we 
    my $binary_mode = $this->{options}->{binary};
    unless(defined $binary_mode) {
	my $using_times = 0;
	for my $k( qw/x x2 y y2 z cb/ ) {
	    if($this->{options}->{$k."data"} and $this->{options}->{$k."data"} =~ m/time/) {
		$using_times = 1;
		last;
	    }
	}
	$binary_mode = !$using_times;
    }

    my ($cbmin,$cbmax) = (undef, undef);
    for my $i(0..$#$chunks) {

	# Figure out, per-curve, whether to use binary or ASCII for that curve.
	# Some 'with' formats require either binary or ASCII, and these
	# are set in the chunks by parseArgs.  Others don't care; for
	# those we use the global $binary_mode.  
	$chunks->[$i]->{binaryCurveFlag} = $chunks->[$i]->{binaryWith} // $binary_mode;


	# Everything else is an image fix
	next if( !($chunks->[$i]->{imgFlag}) );
	
	# Fix up gnuplot ranging bug for images
	unless( $i or 
		$chunks->[$i]->{options}->{xrange} or
		$chunks->[$i]->{options}->{yrange}
	    ) {
	    if($chunks->[$i]->{ArrayRec} eq 'array') {
		# Autorange using matrix locations -- pixels overlap by 0.5 on bottom and top.
		$chunks->[$i]->{options}->{xrange} = [ -0.5, $chunks->[$i]->{data}->[0]->dim(1) - 0.5 ];
		$chunks->[$i]->{options}->{yrange} = [ -0.5, $chunks->[$i]->{data}->[0]->dim(2) - 0.5 ];
	    } else {
		# Autorange using x and y ranging -- sleaze out of matching gnuplot's algorithm by
		# guessing at dx and dy.
		my($xmin,$xmax) = $chunks->[$i]->{data}->[0]->slice("(0)")->minmax;
		my($ymin,$ymax) = $chunks->[$i]->{data}->[0]->slice("(1)")->minmax;

		my $dx = ($xmax-$xmin) / $chunks->[$i]->{data}->[0]->dim(1) * 0.5;
		$chunks->[$i]->{options}->{xrange} = [$xmin - $dx, $xmax + $dx];
		
		my $dy = ($ymax-$ymin) / $chunks->[$i]->{data}->[0]->dim(2) * 0.5;
		$chunks->[$i]->{options}->{yrange} = [$ymin - $dy, $ymax + $dy];
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

    # This is the cbrange kludge.  We use the same localization trick
    # as for the whole options hash, only this time on just the single
    # keyword (in case we're not using a dcloned copy of the hash).
    $o = $this->{options}->{cbrange};
    local($this->{options}->{cbrange});
    if( defined($cbmin)   or   defined($cbmax) ) {
	$this->{options}->{cbrange} = [$cbmin, $cbmax];
    } else {
	$this->{options}->{cbrange} = $o;
    }

    # Since we accept ranges as curve options, but they are only allowed in the first curve of
    # a multiplot, we don't allow ranges in later curves to be emitted.  This is a hack, 
    # since the alternatives are (a) disallowing all curve option ranges (inconvenient), 
    # or (b) trying to merge all ranges, which in turn requires parsing all the available
    # tuple sizes to figure matrix values (which is tedious and I'm too lazy right now).
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
	if($rangeflag) {
	    print STDERR "plot: WARNING: range specifiers aren't allowed as curve options after the first\ncurve.  I ignored $rangeflag of them. (You can also use plot options for ranges)\n";
	}
    }
    
    ##########
    # First: Emit the plot options lines that go above the plot command.  We do this 
    # twice -- once for the main plot command and once for the syntax test.
    my $plotOptionsString = _emitOpts($this->{options}, $pOpt);
    my $testOptionsString;
    {
	local($this->{options}->{terminal}) = "dumb";
	local($this->{options}->{output}) = ' ';
	$testOptionsString = _emitOpts($this->{options}, $pOpt);
    }

    ##########
    # Second: generate the plot command with the fences in it. (fences are emitted in _emitOpts)
    my $plotcmd =  ($this->{options}->{'3d'} ? "splot " : "plot ") . 
	join( ", ", 
	      map { 
		  _emitOpts($chunks->[$_]->{options}, $cOpt, $this);
	      } (0..$#$chunks)
	);

    ##########
    # Third:  Break up the plot command so we can insert data specifiers in each location
    my @plotcmds = split /$cmdFence/, $plotcmd;
    if(@plotcmds != @$chunks+1) {
	barf "This should never happen, but it did.  That's odd.  I give up.";
    }

    ##########
    # Fourth: rebuild the plot command by inserting the format string and data spec for each piece,
    # instead of the placeholder fence strings.
    #
    # Image-style formats use binary matrix format rather than ordinary binary format and must
    # be handled slightly differently.
    #
    my $testcmd;
    {
	my $fl = shift @plotcmds;
	$plotcmd =  $plotOptionsString . $fl;
	$testcmd =  $testOptionsString . $fl;
    }

    for my $i(0..$#plotcmds){
	my($pchunk, $tchunk);
	
	if( $chunks->[$i]->{imgFlag} ) {
	    # It's an image -- always use a binary matrix to push the image out.

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
	    $chunks->[$i]->{testdata} = "." x ($chunks->[$i]->{tuplesize} * 8);

	} else {
	    # It's a non-image plot.  Calculate whether binary or ASCII output.
	    # First, check the per-chunk flag (if set).  If it's not, then 
	    # use the global flag.


	    if( $chunks->[$i]->{binaryCurveFlag} ) {
		my $fstr = "%double" x $chunks->[$i]->{tuplesize};
		
		# The specifiers are identical, except that one gets a length of 1 and the other gets
		# the correct length.   The map statement ensures the main and test cmd get identical 
		# sprintf templates.
		($pchunk, $tchunk) = map {
		    sprintf(" '-' binary %s=(%d) format=\"%s\" %s",
			    $chunks->[$i]->{ArrayRec},
			    $_, 
			    $fstr, 
			    $plotcmds[$i]);
		} ($chunks->[$i]->{data}->[0]->dim(0), 1);
		
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
	$testcmd .= $tchunk;

    }
	
    $plotcmd .= "\n";


    { 
	my $tc = $this->{options}->{topcmds};
	if(defined($tc)) {
	    $plotcmd = (   ((ref $tc) eq 'ARRAY') ? 
			   join("\n",@$tc,$plotcmd) : 
			   $tc."\n".$plotcmd
		);
	}
    }

    my $postTestplotCheckpoint = 'xxxxxxx Plot succeeded xxxxxxx';
    my $print_checkpoint = "; print \"$postTestplotCheckpoint\"";
    $testcmd .= "$print_checkpoint\n";


    #######
    # Fifth: add extracmds, if necessary
    { 
	my $ec = $this->{options}->{extracmds};
	if(defined($ec)) {
	    $plotcmd .= (   ((ref $ec) eq 'ARRAY') ? 
			   join("\n",@$ec,"") :
			    $ec."\n"
		);
      }
    }

    ##########
    # Sixth: put data and final checkpointing on the test command
    $testcmd .= join("", map { $_->{testdata} } @$chunks);

    $PDL::Graphics::Gnuplot::last_plotcmd = $plotcmd;
    $PDL::Graphics::Gnuplot::last_testcmd = $testcmd;


    if($PDL::Graphics::Gnuplot::DEBUG) {
	print "plot command is:\n$plotcmd\n";
    }


    #######
    # Seventh: the commands are assembled.  Now test 'em by sending the test command down the pipe.
    my $checkpointMessage;
    if($check_syntax) {
	_printGnuplotPipe( $this, "syntax", $testcmd );
	$checkpointMessage = _checkpoint($this,"syntax");
	
	if(defined $checkpointMessage && $checkpointMessage !~ /^$postTestplotCheckpoint/m)
	{
	    $checkpointMessage =~ s/$print_checkpoint//;
	    barf "Gnuplot error: \"$checkpointMessage\" while sending plot cmd \"$testcmd\"";
	}
    }

    ##############################
    ##############################
    ##### Finally..... send the actual plot command to the gnuplot device.

    _printGnuplotPipe( $this, "main", $plotcmd);


    for my $chunk(@$chunks){
	my $p;
	if($chunk->{imgFlag}) {
	    # Currently all images are sent binary
	    $p = $chunk->{data}->[0]->double->copy;
	    _printGnuplotPipe($this, "main", ${$p->get_dataref});

	} elsif( $chunk->{binaryCurveFlag}  ) {
	    # Send in binary if the binary flag is set.

	    $p = pdl(@{$chunk->{data}})->mv(-1,0)->double->copy;
	    _printGnuplotPipe($this, "main", ${$p->get_dataref});

	} else {
	    # Not in binary mode - send this chunk in ASCII.  Each line gets one tuple, followed
	    # a line with just "e".

	    if(ref $chunk->{data}->[0] eq 'PDL') {
		# It's a collection of PDL data only.
		$p = pdl(@{$chunk->{data}})->slice(":,:"); # ensure at least 2 dims
		$p = $p->mv(-1,0);                         # tuple dim first, rows second

		# Emit $p as a collection of " " separated lines, followed by "e".
		_printGnuplotPipe($this,
				  "main",
				  join("\n", map { join(" ", $_->list) } $p->dog)  .  "\ne\n"
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

		_printGnuplotPipe($this, "main", $s);
	    }
	}
    }
	
    my $plotWarnings = _checkpoint($this, "main", 'printwarnings');
    

    ##############################
    # Finally, finally ...  send cleanup commands...
    my $cleanup_cmd = "";

    # Set any persistent values back to defaults here...
    {
	my $bc = $this->{options}->{bottomcmds};
	if(defined($bc)){
	    $cleanup_cmd = (  (ref($bc) eq 'ARRAY') ?
			      join( "\n", $bc,"" ) :
			      $bc."\n"
		);
	}

    } 
    if( $this->{options}->{multiplot} ) {
	# In multiplots we can clean up most things but not all.
	# Maybe more cleanup could be added here...
	$cleanup_cmd .= "set size noratio\nset view noequal\nset view 60,30,1.0,1.0\n";
    } else {
	# Outside of multiplots we can clean up everything.
	$cleanup_cmd .= "reset\n";
    }

    if($check_syntax) {
	$PDL::Graphics::Gnuplot::last_testcmd .= $cleanup_cmd;
	_printGnuplotPipe($this, "syntax", $cleanup_cmd);
	$checkpointMessage= _checkpoint($this, "syntax", 'printwarnings');
	if($checkpointMessage) {
	    barf "Gnuplot error: \"$checkpointMessage\" after syntax-checking cleanup cmd \"$cleanup_cmd\"\n";
	}
    }
    
    $PDL::Graphics::Gnuplot::last_plotcmd .= $cleanup_cmd;
    _printGnuplotPipe($this, "main", $cleanup_cmd);
    $checkpointMessage= _checkpoint($this, "main", 'printwarnings');
    if($checkpointMessage) {
	barf "Gnuplot error: \"$checkpointMessage\" after sending cleanup cmd \"$cleanup_cmd\"\n";
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
    # Plot elements that are to be treated
    #
    sub parseArgs
    {
	my $this = shift;


	##############################
	# Parse curve option / data chunks.

	my @args = @_;
	
	my $is3d = $this->{options}->{'3d'} // 0;
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
	    # Array refs are allowed in some curve options, but only as values of key/value
	    # pairs -- so any list refs glommed in with a bunch of PDLs are data.
	    my $nextDataIdx = first { (ref $args[$_] ) and 
				      (ref($args[$_]) =~ m/^PDL$/)} $argIndex..$#args;
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
	    unless($chunk{options}{'with'}) {
		$chunk{options}{'with'} = [$this->{options}->{'globalwith'} || "lines"];
	    }

	    # validate "with" and get imgFlag and tupleSizes.
	    our $plotStyleProps; # declared below
	    my @with = split (/\s+/,$chunk{options}{'with'}->[0]);
	    
	    # Look for the plotStyleProps entry.  If not there, try cleaning up the with style
	    # before giving up entirely.
	    unless( exists( $plotStyleProps->{$with[0]}->[0] ) ) {
		# Try pluralizing and lc'ing if that works...
		if($with[0] !~ m/s$/i  and  exists( $plotStyleProps->{lc $with[0].'s'} ) ) {
		    $with[0] = lc $with[0].'s';
		    shift @{$chunk{options}{'with'}};
		    unshift @{$chunk{options}{'with'}},@with;
		} else {
		    # nope.  throw a fit.
		    barf "invalid plotstyle 'with ".($with[0])."' in plot\n";
		}
	    }

	    # Image flag and base tuplesizes allowed for this plot style...
	    my $imgFlag    = $plotStyleProps->{$with[0]}->[ 2 ];
	    my $tupleSizes = $plotStyleProps->{$with[0]}->[ !!$is3d ];
	   
	    $chunk{binaryWith} = $plotStyleProps->{$with[0]}->[ 3 ];
	    
	    # Reject disallowed plot styles
	    unless(ref $tupleSizes) {
		barf "plotstyle 'with ".($with[0])."' isn't valid in $ND plots\n";
	    }

	    # Additional columns are needed for certain 'with' modifiers. Figure 'em, cheesily...
	    my $ExtraColumns = 0;
	    map { $ExtraColumns++ } grep /(palette|variable)/,@with;
	    
	    ##############################
	    # Figure out what size of tuple we have...
	    my $NdataPiddles = $nextOptionIdx - $argIndex;

	    # Check in case it was explicitly set [do we need this?]
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
		    barf "Found $NdataPiddles PDLs for $ND plot type 'with ".($with[0])."', which needs one of (".join(",",@$tupleSizes).")\n";
		}
	    }

	    my @dataPiddles   = matchDims( @args[$argIndex..$nextOptionIdx-1] );

	    ##############################
	    # A little aside:  streamline the common optimization case -- 
	    # if the user specified "image" but handed in an RGB or RGBA image, 
	    # bust it up into components and update the 'with' accordingly.
	    if( $imgFlag ) {
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

	    $chunk{tuplesize} = @dataPiddles;
	    
	    # Make sure there is a using spec, in case one wasn't given
	    $chunk{options}->{using} = join(":",1..$chunk{tuplesize}) 
		unless exists($chunk{options}->{using});

	    # Check number of lines threaded into this tupleset; make sure everything 
	    # is consistent...
	    my $ncurves;

		
	    if($imgFlag || $is3d){
		# Images should never get a label unless one is explicitly set
		$chunk{options}->{legend} = undef unless( exists($chunk{options}->{legend}) );
		$spec_legends = 1;

		# For the image case glom everything together into one 3-dimensional PDL, 
		# pre-inverted so that the 0 dim runs across column.
		
		if($dataPiddles[0]->dims < 2) {
		    barf "Image plot types require at least a 2-D input PDL\n";
		}

		my $p = pdl(@dataPiddles);

		if( $p->dims > 3 ) {
		    barf "Image data has more than 3 dimensions!\n";
		}

		# Coerce into 3 dimensions, with (col, ix, iy).
		if( $p->dims == 2) {
		    $p = $p->dummy(0,1);
		} else {
		    $p = $p->mv(-1,0);
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

		if($chunk{options}->{legend} and 
		   @{$chunk{options}->{legend}} and 
		   @{$chunk{options}->{legend}} != $ncurves
		    ) {
		    barf "Legend has ".(0+@{$chunk{options}->{legend}})." entries; but ".($ncurves)." curves supplied!";
		}

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
		push @chunks, \%chunk;
	    }

	    $Ncurves += $ncurves;
	    $chunk{imageflag} = $imgFlag;

	    
	    $argIndex = $nextOptionIdx;
	}
	
	return (\@chunks, $Ncurves);
    } # end of ParseArgs nested sub


    # nested sub inside plot
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
	    
	    # flatten everything down if need be.  (no image threading allowed)
	    if($data[0]->ndims <= 2){
		return @data;
	    } else {
		return map { $_->mv(0,-1)->clump(-2)->mv(-1,0)->sever } @data;
	    }
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
		    barf "plot(): row count disagreement:  ".(0+@$_)." != $nelem\n"
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
    local($this->{options}->{'globalwith'}) = 'lines';
    plot($this,@_);
}

=head2 points

=for ref

Generates plots with points, by default. Shorthand for C<plot(globalwith =E<gt> 'points', ...)>

=cut

sub points {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'globalwith'}) = 'points';
    plot($this,@_);
}

=head2 image

=for ref

Displays an image (either greyscale or RGB)

=cut

sub image {
    my $this = _obj_or_global(\@_);
    local($this->{options}->{'globalwith'}) = "image";
    plot($this, @_);
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
    my $test_preamble = "set terminal dumb\nset output \" \"\n";

    my $checkpointMessage;
    if($check_syntax){
	$PDL::Graphics::Gnuplot::last_testcmd = $test_preamble . $command;
	_printGnuplotPipe( $this, "syntax", $test_preamble . $command);
	$checkpointMessage = _checkpoint($this, "syntax");
	if($checkpointMessage) {
	    barf("Gnuplot error: \"$checkpointMessage\" while sending multiplot command.");
	} 
    }
    
    $PDL::Graphics::Gnuplot::last_plotcmd = $preamble . $command;
    _printGnuplotPipe( $this, "main", $preamble . $command);
    $checkpointMessage = _checkpoint($this,"main");
    if($checkpointMessage){
	barf("Gnuplot error: \"$checkpointMessage\" while sending final multiplot command.");
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
	barf("Gnuplot error: unset multiplot failed!\n$checkpointMessage");
    }

    $this->{options}->{multiplot} = 0;
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
	for my $i(0..length($k)-1) {
	    my $s = substr($k,0,$i+1);
	    if(exists($hash->{$s})) {
		push(@{$hash->{$s}},$k);
	    } else {
		$hash->{$s} = [$k];
	    }
	}
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

    'dump'      => ['b', sub { "" },undef, undef,
		    '[pseudo] Redirect gnuplot commands to stdout for inspection'
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

    'globalwith'=> ['s', sub { "" }, undef, undef,
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

    'justify'   => [sub { my($old,$new,$opt) = @_;
			  if($new > 0) {
			      $opt->{'size'} = ["ratio ".(-$new)];
			      return undef;
			  } else {
			      die "justify: positive value needed\n";
			  }
		    }, 
		    sub { '' }, undef, undef,
		    '[pseudo] Set aspect ratio (equivalent to: size=>["ratio",<r>])'
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
    'cblabel'   => ['l',undef,  ['colorbox'], undef,
		    'sets the label on the color box axis'
    ],
    'cbmtics'   => ['b','b',    ['colorbox'], undef,
		    'cbmtics=>1 to use months-of-year tick labels on the color box axis'
    ],
    'cbrange'   => ['l','range',['colorbox'], undef,
		    'controls rendered range of color data values: cbrange=>[<min>,<max>]'
    ],
    'cbtics'    => ['l','l',  ['colorbox'], undef,
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
    'format'    => [sub { die "format: use <axis>tics instead\n"; }
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
    'mxtics'    => ['s','s',undef,undef,
		    'set and control minor ticks on the X axis: mxtics=><freq>'
    ],
    'mx2tics'   => ['s','s',undef,undef,
		    'set and control minor ticks on the X2 axis: mx2tics=><freq>'
    ],
    'mytics'    => ['s','s',undef,undef,
		    'set and control minor ticks on the Y axis: mytics=><freq>'
    ],
    'my2tics'   => ['s','s',undef,undef,
		    'set and control minor ticks on the Y2 axis: my2tics=><freq>'
    ],
    'mztics'    => ['s','s',undef,undef,
		    'set and control minor ticks on the Z axis: mztics=><freq>'
    ],
    'object'    => ['N','N',undef,undef,
		    'define objects to be overlain on plot (numeric index; see docs)'
    ],
    'offsets'   => ['l','l',undef,undef,
		    'define inside-axis blank margin (science units): [<l>,<r>,<t>,<b>]'
    ],
    'origin'    => ['l','l',undef,undef,
		    'set 2-D origin of the plotting surface in relative screen coordinates'
    ],
    'output'    => [sub { barf("Don't set output as a plot option; use the constructor\n"); },
		    'q',undef,3,
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
    'size'      => ['l','l',undef,undef,
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
    'terminal'  => [sub { "Don't set terminal as a plot option; use the constructor\n" },
		    undef,undef,1,
		    'Set the output device type and device dependent options (see docs)\n'
    ],
    'termoption'=> ['H','H',undef,2,
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

			       while( defined($v[0]) and ($v[0] =~ m/^\s*\-?((\d+\.?\d*)|(\d*\.\d+))([eE][\+\-]\d*)?\s*$/ ) ) {
				   push(@numbers, shift @v);
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
    'x2range'   => ['l','range',undef,undef,
		    'set range of X2 axis: x2range=>[<min>,<max>]'
    ],
    'x2tics'    => ['l','l',undef,undef,
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
    'xrange'    => ['l','range',undef,undef,
		    'set range of X axis: xrange=>[<min>,<max>]'
    ],
    'xtics'     => ['l','l',undef,undef,
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
    'y2range'   => ['l','range',undef,undef,
		    'set range of Y2 axis: y2range=>[<min>,<max>]'
    ],
    'y2tics'    => ['l','l',undef,undef,
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
    'ytics'     => ['l','l',undef,undef,
		    'Control tick mark formatting (Y axis; see docs)'
    ],
    'ylabel'    => ['l','ql',undef,undef,
		    'sets label for the Y axis.  See docs for size/color/font options'
    ],
    'ymtics'    => ['b','b',undef,undef,
		    'ymticks=>1 to use months-of-year tick labels on Y axis'
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
    'zrange'    => ['l','range',undef,undef,
		    'set range of Z axis: zrange=>[<min>,<max>]'
    ],
    'zzeroaxis' => ['l','l',undef,undef,
		    'if set, draw a line through (X=0,Y=0) on a 3-D plot.  See docs'
    ],
    'zero'      => ['s','s',undef,undef,
		    'Sets the default threshold for values approaching 0.0'
    ],
    'ztics'     => ['l','l',undef,undef,
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
    'data'     => [sub { barf "mustn't specify data as a curve option...\n" },
		   sub { return " $cmdFence "; },
		   undef,5
		   ],
    'using'    => ['l','cl',undef,6],        # using clauses in order (straight passthrough)
# legend is a special case -- it gets parsed as a list but emitted as a quoted scalar.
    'legend'   => ['l', sub { if(defined($_[1]) and $_[1]->[0]) {return "title \"$_[1]->[0]\"";} else {return "notitle"}},
		   undef, 7],
    'axes'     => [['x1y1','x1y2','x2y1','x2y2'],'cs',undef,8],
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
#   1:  "3dts" Typle sizes (columns of data) that are allowed by this plot style for 
#              3-D plots (with the gnuplot "plots" command).  If this plot style doesn't
#              work in 3-D, then the entry should be a false value instead.
#
#   2:  img    This is a flag indicating whether it is an image format plot (which accepts
#              2-D matrix data in each "column").  If false, the column is a 1-D collection
#              of values.
# 
#   3:  bin   0/1/undef - 0: ASCII data required for this plot type; 1: binary data required.
#


our $plotStyleProps ={
### key                ts         3dts  img  bin
    boxerrorbars   => [ [3,4,5],  0,      0, undef ],
    boxes          => [ [2,3],    0,      0, undef ],
    boxxyerrorbars => [ [4,6],    0,      0, undef ],
    candlesticks   => [ [5],      0,      0, undef ],
    circles        => [ [3],      0,      0, undef ],
    dots           => [ [-1,2],   [3],    0, undef ],
    filledcurves   => [ [-2,3],   0,      0, undef ],
    financebars    => [ [5],      0,      0, undef ],
    fsteps         => [ [-1,2],   0,      0, undef ],
    histeps        => [ [-1,2],   0,      0, undef ],
    histogram      => [ [2,3],    0,      0, undef ],
    newhistogram   => [ [2,3],    0,      0, undef ],
    image          => [ [-1,3],   [-1,4], 1, 1     ],
    impulses       => [ [-1,2,3], [3,4],  0, undef ],
    labels         => [ [3],      [4],    0, 0     ], 
    lines          => [ [-1,2],   [-1,3], 0, undef ],
    linespoints    => [ [-1,2],   [-1,3], 0, undef ],
    points         => [ [-1,2],   [-1,3], 0, undef ],
    rgbalpha       => [ [-4,6],   [7],    1, 1     ],
    rgbimage       => [ [-3,5],   [6],    1, 1     ],
    steps          => [ [-1,2],   0,      0, undef ],
    vectors        => [ [4],      [6],    0, undef ],
    xerrorbars     => [ [-2,3,4], 0,      0, undef ],
    xyerrorbars    => [ [-3,4,6], 0,      0, undef ],
    yerrorbars     => [ [-2,3,4], 0,      0, undef ],
    xerrorlines    => [ [-3,4],   0,      0, undef ],
    xyerrorlines   => [ [-4,6],   0,      0, undef ],
    yerrorlines    => [ [-3,4],   0,      0, undef ],
    pm3d           => [ 0,        [-1,4], 1, 1 ]
};

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
	if(defined $knum) {
	    if(ref $v eq 'ARRAY') {
		unshift(@$v, $knum);
	    } else {
		$v = [$knum, $v];
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
	    # If the parser entry is an array ref, it is interpreted as a list of routines to call in order.
	    # This enables certain types of error checking (notably multiplot interlocks) without too much 
	    # extra hassle in the parse table.
	    my $p = $parser;
	    $parser = sub { 
		my $ret;
		for my $pp(@$p) { 

		    if(ref $pp eq 'CODE') {
			$ret = &$pp(@_);
		    } elsif (ref($_pOHInputs->{$pp}) eq 'CODE') {
			$ret = &{$_pOHInputs->{$pp}}(@_);
		    } else {
			barf "The parser blew up while trying to parse data type '$TableEntry->[0]'! Help!\n";
		    }
		}
		return $ret;
	    };
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
		 return 0 unless($_[1]);                              # false value yields false
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
    my @keys = sort { (($table->{$a}->[3] // 999) <=> ($table->{$b}->[3] // 999)) || 
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

our $_OptionEmitters = {
    #### Default output -- a collection of terms with spaces between them as a plot option
    ' ' => sub { my($k,$v,$h) = @_; 
		 return "" unless(defined($v));
		 if(ref $v eq 'ARRAY') {
		     return join(" ",("set",$k,map {$_ // "" } @$v))."\n";
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
		  return "" unless defined($v);
		  return "set $k $v\n" if($v=~m/^t/i);
		  return "set $k\n";
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
			      return ($v?"":"un")."set $k $v\n";
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

    "NL" => sub { my($k,$v,$h) = @_;
		 return "" unless(defined $v);
		 if(ref $v ne 'ARRAY') {
		     barf "non-array value '$v' found for numeric-indexed option '$k' -- not allowed";
		 }
		 return join ("", map { my $l;
					if(defined($v->[$_])) {
					    $l = "set   $k $_ ";
					    if(ref $v->[$_] eq 'ARRAY') {
						$v->[$_]->[0] = "\"$v->[$_]->[0]\""
						    unless($v->[$_]->[0] =~ m/^\".*\"$/);
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
		     return "set $k ".join(" ",@$v)."\n" if($v->[0] =~ m/^\s*r/i);


		     # first element is an empty range specifier - emit.
		     return "set $k ".join(" ",@$v)."\n" if($v->[0] =~ m/\s*\[\s*\]/);
		     
		     # first element has a nonempty range specifier (naked or not).
		     if($v->[0] =~ m/\:/) {
			 unless($v->[0] =~ m/^\s*\[/) {
			     # the first char was not a '['; assume it is a naked range and patch accordingly.
			     $v->[0] = "[$v->[0]]";
			 }
			 # Now the first element is a patched up range and the whole shebang can be emitted.
			 return "set $k ".join(" ",@$v)."\n";
		     }
		     # If we got here, the first element has no ':'.  Treat the first two elements as numbers and make a range 
		     # specifier out of 'em, then emit.
		     return sprintf("set %s [%s:%s] %s\n", $k, $v->[0] // "", $v->[1] // "", join(" ",@{$v}[2..$#$v]));
    },

    "crange" => sub { my($k,$v,$h) = @_;
		      return "" unless(defined $v);
		      return "$v" if(ref $v ne 'ARRAY');
		      return sprintf(" [%s:%s] ",$v->[0] // "", $v->[1] // "");
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
    inch => 1,
    in   => 1,
    char => 16,
    pt   => 72,
    point=> 72,
    points=>72,
    px   => 72,
    pixel=> 72,
    pixels=>72,
    mm   => 25.4,
    cm   => 2.54
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
    'aqua'     => { unit=>'pt', desc=> 'Aqua terminal program on MacOS X (MacOS default device)',
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

    'apollo'   => "Apollo terminal driver                 [NS: ancient]",
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
	unit=>'char',desc=>"dumb terminal (ASCII output)",
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
    'gif'    => {unit=>'px',desc=>"Graphics Interchange Format (venerable but supported)",
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
    'jpeg'   => {unit=>"px",desc=>"JPEG image file output",
		 opt=>[ qw/ interlace linewidth dashlength rounded butt font enhanced size crop background output /]},
    'kyo'    => "Kyocera laserprinter native format     [NS: obsolete]",
    'latex'  => {unit=>'in',desc=>"EPS output tailored for LaTeX (see also 'epslatex')",
		 opt=>[ ['default', 'b','cff','accept whatever font is in the embedding document'],
			['courier', 'b','cff','force font to Courier'],
			['roman',   'b','cff','force font to Roman style (e.g. Times)'],
			['fontsize','s','cv', 'set font size (in points)'],  # special entry 'coz latex wants no "fontsize" keyword.
			qw/size rotate output/]},
    'linux'  => {unit=>'px',desc=>"Render to a screen under Linux",
		 opt=>['output']},
    'lua'    => "Lua script output                      [NS: obsolete]",
    'macintosh'=>{unit=>'px',desc=>"Direct rendered Macintosh window (MacOS X? Or earlier?)",
		  opt=>[ ['gx',       'b','cf', 'Enable or disable gx (what is this?)'],
			 ['singlewin','b','cff','Put output into a single window (oppose "multiwin")'],
			 ['multiwin', 'b','cff','Allow multiple plot windows'],
			 ['vertical', 'b','cf', 'rotate (or not) vertical text'],
			 'size'
		      ]},
    'lua'    => "Lua script output                      [NS: obsolete]",
    'mf'     => "Metafont output (plot as TeX glyph)    [NS: crazy]",
    'mgr'    => "MGR window system                      [NS: obsolete]",
    'mif'    => "FrameMaker MIF format v3.0             [NS: obsolete]",
    'mp'     => "MetaPost metaformat for graphice       [NS: obsolete]",
    'next'   => "NeXT (NeXTstep) file format (RIP Jobs) [NS: ancient]",
    'openstep'=>"Openstep (NeXTStep followon)           [NS: obsolete]",
    'pbm' => {unit=>"px",desc=>"Portable BitMap format output",
	      opt=>[ ['fontsize','s','cv','font size (in pixels/points)'],
		     qw/monochrome color size output/]},
    'pdf'    => {unit=>'in',desc=>"Portable Document Format output",
		 opt=>[ qw/monochrome color enhanced font linewidth rounded butt solid dashed dashlength size output/ ]},
    'pdfcairo'=>{unit=>'in',desc=>"PDF output via Cairo 2-D plotting library",
		 opt=>[ 'enhanced',
			['monochrome','b', sub{return $_[1]?" mono ":""},
			                         "Generate a B/W plot (see 'color') if true"], # shield user from mono/monochrome
			qw/color solid dashed font linewidth rounded butt dashlength size output/ ]},
    'pm'     => "OS/2 presentation manager              [NS: ancient]",
    'png'    => {unit=>"px",desc=>"PNG image output",
		 opt=>[ qw/transparent interlace/,
			['truecolor','b','cf','Enable or disable true color (RGB) output'],
			qw/rounded butt linewidth dashlength tiny small medium large giant font enhanced size crop background output/]},
    'pngcairo'=>{unit=>'px',desc=>"PNG image output via Cairo 2-D plotting library",
		 opt=>[ 'enhanced',
			['monochrome','b',sub{return $_[1]?" mono ":""},
			                          "Generate a B/W plot (see 'color') if true"], # shield user from mono/monochrome
			qw/color solid dashed transparent crop font linewidth rounded butt dashlength size output/ ]},
    'postscript'=>{unit=>'in',desc=>"Postscript file output",
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
    'svg'     =>{unit=>'in',desc=>"Scalable Vector Graphics (SVG) output",
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
    'wxt'     =>"wxWidgets library                      [NS: obsolete]",
    'x11'     =>{unit=>"px",desc=>"X Windows display",
		 opt=>[ 'output_',
			['title','s','cq','Window title (in title bar)'],
			qw/enhanced font linewidth solid dashed/,
			['persist','b','cf','enable (or disable) persistence after plotting is done'],
			['raise',  'b','cf','enable (or disable) raising the window to the top on plot'],
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

    $termTab->{$k} = { desc => $termTabSource->{$k}->{desc},
		       unit => $termTabSource->{$k}->{unit},
		       opt  => [ $terminalOpt, 
				 undef, # This gets filled in on first use in the constructor.
				 "$k terminal options"
			   ]};
}

=head2 terminfo - print out information about gnuplot syntax

=for usage

    use PDL::Graphics::Gnuplot qw/terminfo/
    terminfo
    terminfo 'aqua'

=for ref

terminfo is a reference tool to describe the Gnuplot terminal types
and the options they accept.  It's mainly useful in interactive
sessions.

=cut

sub terminfo {
    my $terminal = shift || '';

    $terminal = shift if($terminal =~ m/PDL::Graphics::Gnuplot/);

    if($termTabSource->{$terminal}) {
	if(ref $termTabSource->{$terminal}) {
	    print STDERR "Gnuplot terminal '$terminal': size default unit is '$termTabSource->{$terminal}->{unit}', options are:\n";
	    for my $name(@{$termTabSource->{$terminal}->{opt}}) {
		my @info = ();

		if(ref $name) {
		    @info = ( $name->[0], $name->[3] );
		} else {
		    @info = ( $name, $termTab_types->{$name}->[2] );
		}
		$info[0] =~ s/\_$//;         #remove trailing underscore on "output_" hack
		printf STDERR "%10s - %s\n",@info;
	    }
	} else {
	    print STDERR "PDL::Graphics::Gnuplot doesn't support '$terminal'.\n$termTabSource->{$terminal}\n";
	}
	return;
    }
    
    if($terminal && $terminal ne 'all'){
	print STDERR "terminfo: terminal '$terminal' isn't recognized.  I'm listing all supported terminals instead.\n\n";
	$terminal = '';
    }

    if(!$terminal || $terminal eq 'all') {

	unless($terminal eq 'all') {
	    print STDERR "('terminfo \"all\"' lists all known terminals, even those not supported)\n\n";
	}

	print STDERR "Gnuplot terminals supported by PDL::Graphics::Gnuplot:\n";
	
	my $s = "";
	for my $k(sort keys %$termTab) {
	    $s .= sprintf("%10s - %s\n",$k,$termTab->{$k}->{desc});
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
	print STDERR $s;
	return;
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
    
    if( $this->{options}->{dump} ) {
	$this->{"in-$suffix"} = \*STDOUT;
	$this->{"pid-$suffix"} = undef; 
	return $this;
    }
    
    my @gnuplot_options = $gnuplotFeatures{persist} ? qw(--persist) : ();
    
    my $in  = gensym();
    my $err = gensym();
    
    my $pid = open3($in,undef,$err,"gnuplot", @gnuplot_options)
	or barf "Couldn't run the 'gnuplot' backend (is gnuplot in your path?)";
    
    $this->{"in-$suffix"}  = $in;
    $this->{"err-$suffix"} = $err;
    $this->{"errSelector-$suffix"} = IO::Select->new($err);
    $this->{"pid-$suffix"} = $pid;

    $this;
}

sub _killGnuplot {
    my $this = shift;
    my $suffix = shift;

    unless(defined($suffix)) {
	for (grep(m/^pid\-(.*)$/,keys %$this)) {
	    _killGnuplot($this,$1) if($1);
	}
	return;
    }
    
    if( defined $this->{"pid-$suffix"})
    {
	if( $this->{"stuck-$suffix"} )
	{
	    kill 'TERM', $this->{"pid-$suffix"};
	}
	else
	{
	    _printGnuplotPipe( $this, $suffix, "exit\n" );
	}
	
	waitpid( $this->{"pid-$suffix"}, 0 ) ;
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

  my $pipein = $this->{"in-$suffix"};
  print $pipein $string;
  print "_printGnuplotPipe-$suffix: $string" if($this->{debug});


  if( $this->{options}{log} )
  {
    my $len = length $string;
    _logEvent($this,
              "Sent to child process (suffix $suffix) $len bytes==========\n" . $string . "\n=========================" );
  }
}

##############################
# _checkpoint -- synchronize the child and parent processes. After
# _checkpoint() returns, we know that we have read all the data from
# the child. Extra data that represents errors is returned. Warnings
# are explicitly stripped out

sub _checkpoint {
    my $this   = shift;
    my $suffix = shift || "main";
    my $pipeerr = $this->{"err-$suffix"};
    
    # string containing various options to this function
    my $flags = shift;
    
    # I have no way of knowing if the child process has sent its error data
    # yet. It may be that an error has already occurred, but the message hasn't
    # yet arrived. I thus print out a checkpoint message and keep reading the
    # child's STDERR pipe until I get that message back. Any errors would have
    # been printed before this
    my $checkpoint = "xxxxxxx Syncronizing gnuplot i/o xxxxxxx";
    
    _printGnuplotPipe( $this, $suffix, "print \"$checkpoint\"\n" );
    
    
    # if no error pipe exists, we can't check for errors, so we're done. Usually
    # happens if($dump)
    return unless defined $pipeerr;
    
    my $fromerr = '';
    
    do
    { 
	# if no data received in 5 seconds, the gnuplot process is stuck. This
	# usually happens if the gnuplot process is not in a command mode, but in
	# a data-receiving mode. I'm careful to avoid this situation, but bugs in
	# this module and/or in gnuplot itself can make this happen
	my $terminal =$this->{options}->{terminal};
	my $delay = ($terminal && $termTab->{$terminal}->{delay}) || 5;
	
	_logEvent($this, "Trying to read from gnuplot (suffix $suffix)");
	
	if( $this->{"errSelector-$suffix"}->can_read($delay) )
	{
	    # read a byte into the tail of $fromerr. I'd like to read "as many bytes
	    # as are available", but I don't know how to this in a very portable way
	    # (I just know there will be windows users complaining if I simply do a
	    # non-blocking read). Very little data will be coming in anyway, so
	    # doing this a byte at a time is an irrelevant inefficiency
	    my $byte;
	    sysread $pipeerr, $byte, 1;
	    $fromerr .= $byte;
	    
	    _logEvent($this, "Read byte '$byte' (0x" . unpack("H2", $byte) . ") from gnuplot $suffix process");
	}
	else
	{
	    _logEvent($this, "Gnuplot $suffix read timed out"); 
	    
	    $this->{"stuck-$suffix"} = 1;
	    
	    barf <<"EOM";
Hmmm, my $suffix Gnuplot process didn't respond for $delay seconds.
This could be a bug in PDL::Graphics::Gnuplot or gnuplot itself -- 
although for some terminals (like x11) it could be because of a 
slow network.  If you don't think it is a network problem, please
report it as a PDL::Graphics::Gnuplot bug.
EOM
	}
    } until $fromerr =~ /\s*(.*?)\s*$checkpoint.*$/ms;
    
    $fromerr = $1;
    
    my $warningre = qr{^(?:Warning:\s*(.*?)\s*$)\n?}m;
    
    if(defined $flags && $flags =~ /printwarnings/)
    {
	while($fromerr =~ m/$warningre/gm)
	{ print STDERR "Gnuplot warning: $1\n"; }
    }
    
    
    # I've now read all the data up-to the checkpoint. Strip out all the warnings
    $fromerr =~ s/$warningre//gm;
    
    # if asked, get rid of all the "invalid command" errors. This is useful if
    # I'm testing a plot command and I want to ignore the errors caused by the
    # test data bein sent to gnuplot as a command. The plot command itself will
    # never be invalid, so this doesn't actually mask out any errors

    if(defined $flags && $flags =~ /ignore_invalidcommand/)
    {
	$fromerr =~ s/^(gnu|multi)plot>\s*(?:$testdataunit_binary|e\b).*$ # report of the actual invalid command
                    \n^\s+\^\s*$                               # ^ mark pointing to where the error happened
                    \n^.*invalid\s+command.*$//xmg;            # actual 'invalid command' complaint
    }
    
    # strip out all the leading/trailing whitespace
    $fromerr =~ s/^\s*//;
    $fromerr =~ s/\s*$//;
    
    return $fromerr;
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

  return unless($this->{options}->{log}); # only log when asked.

  my $t1 = tv_interval( $this->{t0}, [gettimeofday] );
  printf STDERR "==== PDL::Graphics::Gnuplot PID %d at t=%.4f: %s\n", $this->{pid},$t1,$event;
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
	$globalPlot = new("PDL::Graphics::Gnuplot") 
	    unless(UNIVERSAL::isa($globalPlot,"PDL::Graphics::Gnuplot"));;
	$this = $globalPlot;
    }
    return $this;
}


=head1 COMPATIBILITY

Everything should work on all platforms that support Gnuplot and Perl. That
said, I<ONLY> Debian GNU/Linux has been tested to work. Please report successes
or failures on other platforms to the author. A transcript of a failed run with
{log => 1} would be most helpful.

=head1 REPOSITORY

L<https://github.com/dkogan/PDL-Graphics-Gnuplot>

=head1 AUTHOR

Dima Kogan, C<< <dima@secretsauce.net> >> and Craig DeForest, C<< <craig@deforest.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Dima Kogan and Craig DeForest

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Perl Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

