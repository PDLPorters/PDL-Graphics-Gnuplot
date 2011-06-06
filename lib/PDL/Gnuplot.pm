package PDL::Gnuplot;

use strict;
use warnings;
use PDL;
use IO::Handle;
use List::Util qw(first);
use Storable qw(dclone);

use feature qw(say);
our $VERSION = 1.00;

$PDL::use_commas = 1;

use base 'Exporter';
our @EXPORT_OK = qw(plot);

# I make a list of all the options. I can use this list to determine if an
# options hash I encounter is for the plot, or for a curve
my @allPlotOptions = qw(3d dump extracmds hardcopy maxcurves nogrid square square_xy title
                        lines points linespoints
                        xlabel xmax xmin
                        y2label y2max y2min
                        ylabel ymax ymin
                        zlabel zmax zmin );
my %plotOptionsSet;
foreach(@allPlotOptions) { $plotOptionsSet{$_} = 1; }

my @allCurveOptions = qw(legend y2 with);
my %curveOptionsSet;
foreach(@allCurveOptions) { $curveOptionsSet{$_} = 1; }


sub new
{
  my $classname = shift;

  my %plotoptions = ();
  if(@_)
  {
    if(ref $_[0])
    {
      if(@_ != 1)
      {
        barf "PDL::Gnuplot->new() got a ref as a first argument and has OTHER arguments. Don't know what to do";
      }

      %plotoptions = %{$_[0]};
    }
    else
    { %plotoptions = @_; }
  }

  if( my @badKeys = grep {!defined $plotOptionsSet{$_}} keys %plotoptions )
  {
    barf "PDL::Gnuplot->new() got option(s) that were NOT a plot option: (@badKeys)";
  }

  my $pipe = startGnuplot( $plotoptions{dump} ) or barf "Couldn't start gnuplot backend";
  say $pipe parseOptions(\%plotoptions);

  my $this = {pipe    => $pipe,
              options => \%plotoptions};
  bless($this, $classname);

  return $this;


  sub startGnuplot
  {
    # if we're simply dumping the gnuplot commands to stdout, simply return a handle to STDOUT
    my $dump = shift;
    return *STDOUT if $dump;


    my $pipe;
    unless( open $pipe, '|-', "gnuplot --persist" )
    {
      say STDERR "Couldn't launch gnuplot";
      return;
    }
    return $pipe;
  }

  sub parseOptions
  {
    my $options = shift;

    # if no options are defined, I'm done
    my $defaultsOnly;
    $defaultsOnly = 1 unless keys %$options;

    # set some defaults
    $options->{ maxcurves } = 100 unless defined $options->{ maxcurves };

    return if $defaultsOnly;


    # make sure I'm not passed invalid combinations of options
    {
      if ( $options->{'3d'} )
      {
        if ( defined $options->{y2min} || defined $options->{y2max} )
        { barf "'3d' does not make sense with 'y2'...\n"; }

        if( $options->{with} =~ /circles/ )
        { barf "At this time gnuplot does not support 3d plotting with circles."; }
      }
      else
      {
        # if (!$options->{colormap})
        # {
        #   if ( defined $options->{zmin} || defined $options->{zmax} || defined $options->{zlabel} )
        #   { barf "'zmin'/'zmax'/'zlabel' only makes sense with '3d' or 'colormap'\n"; }
        # }

        if ( defined $options->{square_xy} )
        { barf "'square'_xy only makes sense with '3d'\n"; }
      }
    }


    my $cmd   = '';


    # set the global style
    {
      my $style = '';

      if($options->{lines}  || $options->{linespoints}) { $style .= "lines"; }
      if($options->{points} || $options->{linespoints}) { $style .= "points"; }

      $cmd .= "set style data $style\n" if $style;
    }

    # grid on by default
    if( !$options->{nogrid} )
    { $cmd .= "set grid\n"; }

    # set the plot bounds
    {
      # If a bound isn't given I want to set it to the empty string, so I can communicate it simply
      # to gnuplot
      $options->{xmin}  = '' unless defined $options->{xmin};
      $options->{xmax}  = '' unless defined $options->{xmax};
      $options->{ymin}  = '' unless defined $options->{ymin};
      $options->{ymax}  = '' unless defined $options->{ymax};
      $options->{y2min} = '' unless defined $options->{y2min};
      $options->{y2max} = '' unless defined $options->{y2max};
      $options->{zmin}  = '' unless defined $options->{zmin};
      $options->{zmax}  = '' unless defined $options->{zmax};

      # if any of the ranges are given, set the range
      $cmd .= "set xrange [$options->{xmin}:$options->{xmax}]\n"    if length( $options->{xmin}  . $options->{xmax} );
      $cmd .= "set yrange [$options->{ymin}:$options->{ymax}]\n"    if length( $options->{ymin}  . $options->{ymax} );
      $cmd .= "set y2range [$options->{y2min}:$options->{y2max}]\n" if length( $options->{y2min} . $options->{y2max} );

      # if ($options->{colormap})
      # {
      #   $cmd .= "set cbrange [$options->{zmin}:$options->{zmax}]\n" if length( $options->{zmin} . $options->{zmax} );
      # }
      # else
      {
        $cmd .= "set zrange [$options->{zmin}:$options->{zmax}]\n"    if length( $options->{zmin}  . $options->{zmax} );
      }
    }

    # set the curve labels, titles
    {
      $cmd .= "set xlabel  \"$options->{xlabel }\"\n" if defined $options->{xlabel};
      $cmd .= "set ylabel  \"$options->{ylabel }\"\n" if defined $options->{ylabel};
      $cmd .= "set zlabel  \"$options->{zlabel }\"\n" if defined $options->{zlabel};
      $cmd .= "set y2label \"$options->{y2label}\"\n" if defined $options->{y2label};
      $cmd .= "set title   \"$options->{title  }\"\n" if defined $options->{title};
    }

    # handle a requested square aspect ratio
    {
      # set a square aspect ratio. Gnuplot does this differently for 2D and 3D plots
      if ( $options->{'3d'})
      {
        if    ($options->{square})    { $cmd .= "set view equal xyz\n"; }
        elsif ($options->{square_xy}) { $cmd .= "set view equal xy\n" ; }
      }
      else
      {
        if( $options->{square} ) { $cmd .= "set size ratio -1\n"; }
      }
    }



    # handle multiple-range styles, such as colormaps and circles
    $options->{style_allcurves} = undef; # placeholder until the following is re-enabled

    # $options->{valuesPerPoint} = 1; # by default, 1 value for each point
    # {
    #   if( $options->{colormap} )
    #   {
    #     # colormap styles all curves with palette. Seems like there should be a way to do this with a
    #     # global setting, but I can't get that to work
    #     $options->{style_allcurves} = 'palette';
    #   }


    #   if( $options->{extraValuesPerPoint})
    #   { $options->{valuesPerPoint} += $options->{extraValuesPerPoint}; }

    #   if( $options->{colormap} )
    #   { $options->{valuesPerPoint}++; }

    #   if( defined $options->{with} && $options->{with} =~ /circles/ )
    #   { $options->{valuesPerPoint}++; }
    # }


    # handle hardcopy output
    {
      if ( $options->{hardcopy})
      {
        my $outputfile = $options->{hardcopy};
        my ($outputfileType) = $outputfile =~ /\.(eps|ps|pdf|png)$/;
        if (!$outputfileType)
        { barf "Only .eps, .ps, .pdf and .png hardcopy output supported\n"; }

        my %terminalOpts =
          ( eps  => 'postscript solid color enhanced eps',
            ps   => 'postscript solid color landscape 10',
            pdf  => 'pdfcairo solid color font ",10" size 11in,8.5in',
            png  => 'png size 1280,1024' );

        $cmd .= "set terminal $terminalOpts{$outputfileType}\n";
        $cmd .= "set output \"$outputfile\"\n";
      }
    }


    # add the extra global options
    {
      if($options->{extracmds})
      {
        foreach (@{$options->{extracmds}})
        { $cmd .= "$_\n"; }
      }
    }

    return $cmd;
  }
}

# the main API function to generate a plot. Input arguments are a bunch of piddles optionally
# followed by a bunch of options for each curve.
#
# The input piddles are a single domain piddle followed by some range piddles.
# If the domain is null, sequential integers (0,1,2...) are used.
# If the domain is null, and we're plotting in 3D, we use an appropriately-sized grid (see below)
# If only a single piddle argument is given, domain==null is assumed
#
# For 3d plots the domain is an Npoints-2-... piddle that contains the (x,y) values for each point

# If the domain is null and we're plotting in 3D, a grid based on the first
# 2-dimensions of the range is used. For instance if the first 2 dims of a range
# are 3x5, the range is plotted on a 3x5 grid with x in 0..2 and y in 0..4

#
# For plots that have more than one value per range, ranges are interpreted to be
# Npoints-NperRange-... piddles
#
# The ranges for each curve can be given in separate arguments to plot(), or stacked in the ranges
# piddles
sub plot
{
  barf( "Plot called with no arguments") unless @_;

  my $this;

  if(!defined ref $_[0] || ref $_[0] ne 'PDL::Gnuplot')
  {
    # plot() called as a global function, NOT as a method.  the first argument
    # can be a hashref of plot options, or it could be the data directly.
    my $plotOptions = {};
    my $arg0 = $_[0];
    if(defined ref $arg0 && ref $arg0 eq 'HASH')
    {
      # arg0 is a hash. Is it plot options or curve options?
      my @plotOptions = grep {defined $plotOptionsSet{$_}} keys %$arg0;

      if(@plotOptions != 0)
      {
        if(scalar @plotOptions != scalar keys %$arg0)
        {
          barf "Got an option hash that isn't completely plot options or non-plot options";
        }

        $plotOptions = shift;
      }
    }

    $this = PDL::Gnuplot->new($plotOptions);
  }
  else
  {
    $this = shift;
  }

  my $pipe        = $this->{pipe};
  my $plotOptions = $this->{options};


  # I split my data-to-plot into similarly-styled chunks
  # pieces of data we're plotting. Each chunk has a similar style
  my ($chunks, $Ncurves) = parseArgs(@_);


  if( scalar @$chunks == 0)
  { barf "plot() was not given any data"; }

  # # if no domain is specified, make a default one
  # if($domain->nelem == 0)
  # {
  #   if( !$plotOptions->{'3d'} )
  #   {
  #     # in 2D, the default domain is simply increasing integers
  #     $domain = sequence($rangelist->[0]->dim(0));
  #   }
  #   else
  #   {
  #     # in 3D, the first 2 dimensions of every range are plotted in a grid
  #     my $domaindims;
  #     foreach my $range(@$rangelist)
  #     {
  #       my @dims = $range->dims;
  #       barf "plot() got a null range" if(! @dims);

  #       # a 1D range gets a degenerate dimension
  #       push( @dims, 1) if(@dims == 1);

  #       if(! $domaindims)
  #       {
  #         # store the domain dimensions if I don't already have them
  #         $domaindims = \@dims;

  #         # generate an Nx2 domain useable by the rest of the code
  #         my $Npoints = $dims[0] * $dims[1];
  #         $domain = zeros(@dims[0..1])->ndcoords->reshape(2,$Npoints)->transpose;
  #       }
  #       else
  #       {
  #         # if I do have them, make sure they match
  #         if($domaindims->[0] != $dims[0] || $domaindims->[1] != $dims[1])
  #         { barf "plot() grid domain mismatch"; }
  #       }

  #       # make the range dimensionality reflect the domain
  #       $range = $range->clump(2);
  #     }
  #   }
  # }



  if($Ncurves > $plotOptions->{maxcurves})
  {
    # this is here in case the user made an error that makes the plotter blow up

    barf <<EOB;
Tried to plot $Ncurves curves.
This exceeds the 'maxcurves' setting.\n
Invoke with a higher 'maxcurves' option if you really want to do this.\n
EOB

  }

  say $pipe plotcmd($chunks, $plotOptions->{'3d'}, $plotOptions->{style_allcurves});

  foreach my $chunk(@$chunks)
  {
    my $tupleSize = $chunk->{tupleSize};
    my $data      = $chunk->{data};
    eval( "_writedata_$tupleSize" . '(@$data, $pipe)');
  }

  flush $pipe;


  # generates the gnuplot command to generate the plot. The curve options are parsed here
  sub plotcmd
  {
    my ($chunks, $is3d, $style_allcurves) = @_;

    my $cmd = '';


    # if anything is to be plotted on the y2 axis, set it up
    if( grep {my $chunk = $_; grep {$_->{y2}} @{$chunk->{options}}} @$chunks)
    {
      if ( $is3d )
      { barf "3d plots don't have a y2 axis"; }

      $cmd .= "set ytics nomirror\n";
      $cmd .= "set y2tics\n";
    }

    if($is3d) { $cmd .= 'splot '; }
    else      { $cmd .= 'plot ' ; }

    $cmd .=
      join(',',
           map
           { map {"'-' " . optioncmd($_, $style_allcurves)} @{$_->{options}} }
           @$chunks);

    return $cmd;



    # parses a curve option
    sub optioncmd
    {
      my $option          = shift;
      my $style_allcurves = shift;

      my $cmd = '';

      if( defined $option->{legend} )
      { $cmd .= "title \"$option->{legend}\" "; }
      else
      { $cmd .= "notitle "; }

      $cmd .= "with $option->{with} " if defined $option->{with};
      $cmd .= "$style_allcurves "     if defined $style_allcurves;
      $cmd .= "axes x1y2 "            if defined $option->{y2};

      return $cmd;
    }
  }

  sub parseArgs
  {
    # Here I parse the plot() arguments.  Each chunk of data to plot appears in
    # the argument list as plot(options, options, ..., data, data, ....). The
    # options are either a hash (reference or inline) or a ref to an array of
    # hashrefs, or can be absent entirely. THE OPTIONS ARE ALWAYS DEFINED ON TOP
    # OF THE PREVIOUS SET OF OPTIONS
    #
    # Based on the options I know the size of the plot tuple. For example,
    # simple x-y plots have 2 values per point, while x-y-z-color plots have
    # 4. The data arguments are one-argument-per-tuple-element.
    # TODO: get implicit domains working
    my @args = @_;

    # options are cumulative. This is a hashref that contains the accumulator
    my $lastOptions = {};

    my @chunks;
    my $Ncurves  = 0;
    my $argIndex = 0;
    while($argIndex <= $#args)
    {
      # First, I find and parse the options in this chunk
      my $nextDataIdx = first {ref $args[$_] && ref $args[$_] eq 'PDL'} $argIndex..$#args;
      last if !defined $nextDataIdx; # no more data. done.

      my %chunk;
      if( $nextDataIdx > $argIndex )
      {
        $chunk{options} = parseOptionsArgs($lastOptions, @args[$argIndex..$nextDataIdx-1]);
      }
      else
      {
        # No options given for this chunk, so use the last ones
        $chunk{options} = [ dclone $lastOptions ];
      }

      # I now have the options for this chunk. Let's grab the data
      $argIndex         = $nextDataIdx;
      my $nextOptionIdx = first {!ref $args[$_] || ref $args[$_] ne 'PDL'} $argIndex..$#args;
      $nextOptionIdx = @args unless defined $nextOptionIdx;

      $tupleSize = getTupleSize($chunk{options});
      my $NdataPiddles = $nextOptionIdx - $argIndex;

      if($NdataPiddles < $tupleSize)
      { barf "plot() needed $tupleSize data piddles, but only got $NdataPiddles"; }

      if($NdataPiddles > $tupleSize)
      {
        $nextOptionIdx = $argIndex + $tupleSize;
        $NdataPiddles = $tupleSize;
      }

      my @dataPiddles   = @args[$argIndex..$nextOptionIdx-1];
      $chunk{data}      = \@dataPiddles;
      $chunk{tupleSize} = $tupleSize;

      $chunk{Ncurves} = countCurvesAndValidate(\%chunk);
      $Ncurves += $chunk{Ncurves};

      push @chunks, \%chunk;

      $argIndex = $nextOptionIdx;
    }

    return (\@chunks, $Ncurves);




    sub parseOptionsArgs
    {
      # my options are cumulative. This variable contains the accumulator
      my $options = shift;

      # I now have my options arguments. Each curve is described by a hash
      # (reference or inline). To have separate options for each curve, I use an
      # ref to an array of hashrefs
      my @optionsArgs = @_;

      # the options for each curve go here
      my @curveOptions = ();

      my $optionArgIdx = 0;
      while ($optionArgIdx < @optionsArgs)
      {
        my $optionArg = $optionsArgs[$optionArgIdx];

        if (ref $optionArg)
        {
          if (ref $optionArg eq 'HASH')
          {
            # add this hashref to the options
            @{$options}{keys %$optionArg} = values %$optionArg;
            push @curveOptions, dclone($options);
          }
          elsif (ref $optionArg eq 'ARRAY')
          {
            # got a list of options. Each element should be a hashref, applying
            # to each successive curve. These intra-chunk options build on each other
            foreach (@$optionArg)
            {
              if(defined ref $_ && ref $_ ne 'HASH')
              { barf "plot() was given an array-ref option that didn't consist of hashrefs-only"; }

              @{$options}{keys %$_} = values %$_;
              push @curveOptions, dclone($options);
            }
          }
          else
          {
            barf "plot() got a reference to a " . ref( $optionArg) . ". I can only deal with HASHes and ARRAYs";
          }
        }
        else
        {
          # this is a scalar. I interpret a pair as key/value
          if ($optionArgIdx+1 == @optionsArgs)
          { barf "plot() got a lone scalar argument $optionArg, where a key/value was expected"; }

          $options->{$optionArg} = $optionsArgs[++$optionArgIdx];
          push @curveOptions, dclone($options);
        }

        $optionArgIdx++;
      }

      return \@curveOptions;
    }

    sub countCurvesAndValidate
    {
      my $chunk = shift;

      # Make sure the domain and ranges describe the same number of data points
      my $data = $chunk->{data};
      foreach (1..$#$data)
      {
        my $dim0 = $data->[$_  ]->dim(0);
        my $dim1 = $data->[$_-1]->dim(0);
        if( $dim0 != $dim1 )
        { barf "plot() was given mismatched tuples to plot. $dim0 vs $dim1"; }
      }

      # make sure I know what to do with all the options
      foreach my $option(@{$chunk->{options}})
      {
        if(my @badKeys = grep {!defined $curveOptionsSet{$_}} keys %$option)
        {
          barf "plot() got some unknown curve options: (@badKeys)";
        }
      }

      # I now make sure I have exactly one set of curve options per curve
      my $Ncurves = countCurves($data);
      my $Noptions = scalar @{$chunk->{options}};

      if($Noptions > $Ncurves)
      { barf "plot() got $Noptions options but only $Ncurves curves. Not enough curves"; }
      elsif($Noptions < $Ncurves)
      {
        # I have more curves then options. I pad the option list with the last option
        my $lastOption = $chunk->{options}[-1];
        push @{$chunk->{options}}, ($lastOption) x ($Ncurves - $Noptions);
      }

      return $Ncurves;



      sub countCurves
      {
        # compute how many curves have been passed in, assuming things thread

        my $data = shift;

        my $N = 1;

        # I need to look through every dimension to check that things can thread
        # and then to compute how many threads there will be. I skip the first
        # dimension since that's the data points, NOT separate curves
        my $maxNdims = List::Util::max map {$_->ndims} @$data;
        foreach my $dimidx (1..$maxNdims-1)
        {
          # in a particular dimension, there can be at most 1 non-1 unique
          # dimension. Otherwise threading won't work.
          my $nonDegenerateDim;

          foreach (@$data)
          {
            my $dim = $_->dim($dimidx);
            if($dim != 1)
            {
              if(defined $nonDegenerateDim)
              {
                barf "plot() was given non-threadable arguments. Got a dim of size $dim, when I already saw size $nonDegenerateDim";
              }
              else
              {
                $nonDegenerateDim = $dim;
              }
            }
          }

          # this dimension checks out. Count up the curve contribution
          $N *= $nonDegenerateDim if $nonDegenerateDim;
        }

        return $N;
      }
    }

    sub getTupleSize
    {
      return 2;
    }
  }
}

# subroutine to write the columns of some piddles into a gnuplot stream. This
# assumes the last argument is a file handle. Generally you should NOT be using
# this directly at all; it's just used to define the threading-aware routines
sub _wcols_gnuplot
{
  wcols @_;
  my $pipe = $_[-1];
  say $pipe 'e';
};

# I generate a bunch of PDL definitions such as
# _writedata_2(x1(n), x2(n)), NOtherPars => 1
# 20 tuples per point sounds like plenty. The most complicated plots Gnuplot can
# handle probably max out at 5 or so
for my $n (2..20)
{
  my $def = "_writedata_$n(" . join( ';', map {"x$_(n)"} 1..$n) . "), NOtherPars => 1";
  thread_define $def, over \&_wcols_gnuplot;
}



1;
