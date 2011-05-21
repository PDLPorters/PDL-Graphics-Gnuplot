package PDL::Gnuplot;

use strict;
use warnings;
use PDL;
use IO::Handle;
use feature qw(say);
our $VERSION = 1.00;

sub new
{
  my ($classname, $plotoptions) = @_;

  $plotoptions = {} unless defined $plotoptions;

  my $pipe = startGnuplot($plotoptions) or barf "Couldn't start gnuplot backend";
  say $pipe parseOptions($plotoptions);

  my $this = {pipe    => $pipe,
              options => $plotoptions};
  bless($this, $classname);

  return $this;


  sub startGnuplot
  {
    # if we're simply dumping the gnuplot commands to stdout, simply return a handle to STDOUT
    my $options = shift;
    return *STDOUT if exists $options->{dump};


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

    # set some defaults
    $options->{ maxcurves } = 100 unless defined $options->{ maxcurves };

    # if no options are defined, I'm done
    return '' unless keys %$options;


    # make sure I'm not passed invalid combinations of options
    # {
    #   if ( $options->{'3d'} )
    #   {
    #     if ( defined $options->{y2min} || defined $options->{y2max} || defined $options->{y2} )
    #     { barf "'3d' does not make sense with 'y2'...\n"; }
    #   }
    #   else
    #   {
    #     if (!$options->{colormap})
    #     {
    #       if ( defined $options->{zmin} || defined $options->{zmax} || defined $options->{zlabel} )
    #       { barf "'zmin'/'zmax'/'zlabel' only makes sense with '3d' or 'colormap'\n"; }
    #     }

    #     if ( defined $options->{square_xy} )
    #     { barf "'square'_xy only makes sense with '3d'\n"; }
    #   }
    # }


    my $cmd   = '';


    # set the global style
    {
      my $style = '';

      $style .= 'lines'              if $options->{lines};
      $style .= 'points'             if $options->{points};
      $style .= " $options->{style}" if $options->{style};

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
      # if ( $options->{'3d'})
      # {
      #   if    ($options->{square})    { $cmd .= "set view equal xyz\n"; }
      #   elsif ($options->{square_xy}) { $cmd .= "set view equal xy\n" ; }
      # }
      # else
      {
        if( $options->{square} ) { $cmd .= "set size ratio -1\n"; }
      }
    }



    # handle multiple-range styles, such as colormaps and circles
    # {
    #   if ($options->{circles})
    #   {
    #     $options->{curvestyleall} = "with circles $options->{curvestyleall}";
    #   }
    #   if ($options->{colormap})
    #   {
    #     # colormap styles all curves with palette. Seems like there should be a way to do this with a
    #     # global setting, but I can't get that to work
    #     $options->{curvestyleall} .= ' palette';
    #   }

    #   my $valuesPerPoint = 1;
    #   if ($options->{extraValuesPerPoint})
    #   { $valuesPerPoint += $options->{extraValuesPerPoint}; }
    #   if ($options->{colormap})
    #   { $valuesPerPoint++; }
    #   if ($options->{circles} )
    #   { $valuesPerPoint++; }
    # }

    # handle some basic setup of the 2nd y-axis, if we're using it
    # {
    #   if ($options->{y2})
    #   {
    #     $cmd .= "set ytics nomirror\n";
    #     $cmd .= "set y2tics\n";
    #   }
    # }

    # handle hardcopy output
    # {
    #   my $outputfile;
    #   my $outputfileType;
    #   if ( $options->{hardcopy})
    #   {
    #     $outputfile = $options->{hardcopy};
    #     ($outputfileType) = $outputfile =~ /\.(eps|ps|pdf|png)$/;
    #     if (!$outputfileType)
    #     { die("Only .eps, .ps, .pdf and .png supported\n"); }

    #     my %terminalOpts =
    #       ( eps  => 'postscript solid color enhanced eps',
    #         ps   => 'postscript solid color landscape 10',
    #         pdf  => 'pdfcairo solid color font ",10" size 11in,8.5in',
    #         png  => 'png size 1280,1024' );

    #     $cmd .= "set terminal $terminalOpts{$outputfileType}\n";
    #     $cmd .= "set output \"$outputfile\"\n";
    #   }
    # }


    # add the extra global options
    {
      if($options->{extracmds})
      {
        foreach (@{$options->{extracmds}})
        { $cmd .= "$_\n"; }
      }
    }

    return $cmd;







# #######################
# # per curve
# 'legend=s{2}'
# 'curvestyle=s{2}'
# # For the specified values, set the legend entries to 'title "blah blah"'
#     if(@{$options->{legend}})
#     {
#       # @{$options->{legend}} is a list where consecutive pairs are (curveID, legend)
#       my $n = scalar @{$options->{legend}}/2;
#       foreach my $idx (0..$n-1)
#       {
#         setCurveLabel($options->{legend}[$idx*2    ],
#                       $options->{legend}[$idx*2 + 1]);
#       }
#     }

# # add the extra curve options
#     if(@{$options->{curvestyle}})
#     {
#       # @{$options->{curvestyle}} is a list where consecutive pairs are (curveID, style)
#       my $n = scalar @{$options->{curvestyle}}/2;
#       foreach my $idx (0..$n-1)
#       {
#         addCurveOption($options->{curvestyle}[$idx*2    ],
#                        $options->{curvestyle}[$idx*2 + 1]);
#       }
#     }

# y2















    return $cmd;
  }
}

sub plot_xy
{
  my $this              = shift;
  my ($x, $y, $options) = @_;

  if ($x->dim(0) != $y->dim(0))
  {
    my @xdims = $x->dims;
    my @ydims = $y->dims;
    barf "ploxy() args must have equal first dimensions. Dims: (@xdims) and (@ydims)";
  }
  my $N = numCurves($x, $y);

  if($N > $this->{options}{maxcurves})
  {
    barf <<EOB;
Tried to exceed the 'maxcurves' setting.\n
Invoke with a higher 'maxcurves' option if you really want to do this.\n
EOB

  }


  my $pipe = $this->{pipe};

  say $pipe plotcmd($N, $options);

  _plotxy_writedata(@_, $pipe);
  flush $pipe;


  # compute how many curves have been passed in, assuming things will thread
  sub numCurves
  {
    my ($x, $y) = @_;

    my $N = 1;
    my $maxNdims = maximum pdl($x->ndims, $y->ndims);

    for my $idim (1..$maxNdims-1)
    {
      my ($dim0, $dim1) = minmax(pdl($x->dim($idim), $y->dim($idim)));

      if ($dim0 == 1 || $dim0 == $dim1)
      {
        $N *= $dim1;
      }
      else
      {
        my @xdims = $x->dims;
        my @ydims = $y->dims;
        barf "ploxy() was given non-threadable arguments. Mismatched dims: (@xdims) and (@ydims)";
      }
    }

    return $N;
  }

  # generates the gnuplot command to generate the plot. The curve options are parsed here
  sub plotcmd
  {
    my ($N, $options) = @_;

    # remove any options that exceed my data
    $options //= [];
    splice( @$options, $N ) if @$options > $N;

    # fill the options list to match the number of curves in length
    push @$options, ({}) x ($N - @$options);

    return 'plot ' . join(',', map {"'-' " . optioncmd($_)} @$options);



    # parses a curve option
    sub optioncmd
    {
      my $option = shift;

      return '';
    }
  }
}

thread_define '_plotxy_writedata(x(n); y(n)), NOtherPars => 1', over
{
  my $pipe = pop @_;
  wcols @_, $pipe;
  say $pipe 'e';
};

1;
