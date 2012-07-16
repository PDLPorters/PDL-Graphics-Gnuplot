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

use base 'Exporter';
our @EXPORT_OK = qw(plot plot3d plotlines plotpoints);

our $VERSION = 0.04;

# when testing plots with ASCII i/o, this is the unit of test data
my $testdataunit_ascii = "10 ";

# if I call plot() as a global function I create a new PDL::Graphics::Gnuplot
# object. I would like the gnuplot process to persist to keep the plot
# interactive at least while the perl program is running. This global variable
# keeps the new object referenced so that it does not get deleted. Once can
# create their own PDL::Graphics::Gnuplot objects, but there's one free global
# one available
my $globalPlot;

# I make a list of all the options. I can use this list to determine if an
# options hash I encounter is for the plot, or for a curve
my @allPlotOptions = qw(3d dump binary log
                        extracmds nogrid square square_xy title
                        hardcopy terminal output
                        globalwith
                        xlabel xmax xmin
                        y2label y2max y2min
                        ylabel ymax ymin
                        zlabel zmax zmin
                        cbmin cbmax);
my %plotOptionsSet;
foreach(@allPlotOptions) { $plotOptionsSet{$_} = 1; }

my @allCurveOptions = qw(legend y2 with tuplesize);
my %curveOptionsSet;
foreach(@allCurveOptions) { $curveOptionsSet{$_} = 1; }


# get a list of all the -- options that this gnuplot supports
my %gnuplotFeatures = _getGnuplotFeatures();



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
        barf "PDL::Graphics::Gnuplot->new() got a ref as a first argument and has OTHER arguments. Don't know what to do";
      }

      %plotoptions = %{$_[0]};
    }
    else
    { %plotoptions = @_; }
  }

  if( my @badKeys = grep {!defined $plotOptionsSet{$_}} keys %plotoptions )
  {
    barf "PDL::Graphics::Gnuplot->new() got option(s) that were NOT a plot option: (@badKeys)";
  }

  my $pipes  = startGnuplot( $plotoptions{dump} );

  my $this = {%$pipes, # %$this is built on top of %$pipes
              options  => \%plotoptions,
              t0       => [gettimeofday]};
  bless($this, $classname);

  _logEvent($this, "startGnuplot() finished");


  # the plot options affect all the plots made by this object, so I can set them
  # now
  _safelyWriteToPipe($this, parseOptions(\%plotoptions));

  return $this;


  sub startGnuplot
  {
    my $dump = shift;
    return {in => \*STDOUT} if($dump);

    my @options = $gnuplotFeatures{persist} ? qw(--persist) : ();

    my $in  = gensym();
    my $err = gensym();

    my $pid =
      open3($in, undef, $err, 'gnuplot', @options)
        or die "Couldn't run the 'gnuplot' backend";

    return {in          => $in,
            err         => $err,
            errSelector => IO::Select->new($err),
            pid         => $pid};
  }

  sub parseOptions
  {
    my $options = shift;

    # set some defaults
    # plot with lines and points by default
    $options->{globalwith} = 'linespoints' unless defined $options->{globalwith};

    # make sure I'm not passed invalid combinations of options
    {
      if ( $options->{'3d'} )
      {
        if ( defined $options->{y2min} || defined $options->{y2max} )
        { barf "'3d' does not make sense with 'y2'...\n"; }

        if ( !$gnuplotFeatures{equal_3d} && (defined $options->{square_xy} || defined $options->{square} ) )
        {
          warn "Your gnuplot doesn't support square aspect ratios for 3D plots, so I'm ignoring that";
          delete $options->{square_xy};
          delete $options->{square};
        }
      }
      else
      {
        if ( defined $options->{square_xy} )
        { barf "'square'_xy only makes sense with '3d'\n"; }
      }
    }


    my $cmd   = '';

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
      $options->{cbmin} = '' unless defined $options->{cbmin};
      $options->{cbmax} = '' unless defined $options->{cbmax};

      # if any of the ranges are given, set the range
      $cmd .= "set xrange  [$options->{xmin} :$options->{xmax} ]\n" if length( $options->{xmin}  . $options->{xmax} );
      $cmd .= "set yrange  [$options->{ymin} :$options->{ymax} ]\n" if length( $options->{ymin}  . $options->{ymax} );
      $cmd .= "set zrange  [$options->{zmin} :$options->{zmax} ]\n" if length( $options->{zmin}  . $options->{zmax} );
      $cmd .= "set cbrange [$options->{cbmin}:$options->{cbmax}]\n" if length( $options->{cbmin} . $options->{cbmax} );
      $cmd .= "set y2range [$options->{y2min}:$options->{y2max}]\n" if length( $options->{y2min} . $options->{y2max} );
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

    # handle 'hardcopy'. This simply ties in to 'output' and 'terminal', handled
    # later
    {
      if ( defined $options->{hardcopy})
      {
        # 'hardcopy' is simply a shorthand for 'terminal' and 'output', so they
        # can't exist together
        if(defined $options->{terminal} || defined $options->{output} )
        {
          barf <<EOM;
The 'hardcopy' option can't coexist with either 'terminal' or 'output'.  If the
defaults are acceptable, use 'hardcopy' only, otherwise use 'terminal' and
'output' to get more control.
EOM
        }

        my $outputfile = $options->{hardcopy};
        my ($outputfileType) = $outputfile =~ /\.(eps|ps|pdf|png)$/;
        if (!$outputfileType)
        { barf "Only .eps, .ps, .pdf and .png hardcopy output supported\n"; }

        my %terminalOpts =
          ( eps  => 'postscript solid color enhanced eps',
            ps   => 'postscript solid color landscape 10',
            pdf  => 'pdf solid color font ",10" size 11in,8.5in',
            png  => 'png size 1280,1024' );

        $options->{terminal} = $terminalOpts{$outputfileType};
        $options->{output}   = $outputfile;
      }

      if( defined $options->{terminal} && !defined $options->{output} )
      {
        print STDERR <<EOM;
Warning: defined gnuplot terminal, but NOT an output file. Is this REALLY what you want?
EOM
      }
    }


    # add the extra global options
    {
      if($options->{extracmds})
      {
        # if there's a single extracmds option, put it into a 1-element list to
        # make the processing work
        if(!ref $options->{extracmds} )
        { $options->{extracmds} = [$options->{extracmds}]; }

        foreach (@{$options->{extracmds}})
        { $cmd .= "$_\n"; }
      }
    }

    return $cmd;
  }
}

sub DESTROY
{
  my $this = shift;

  # if we're stuck on a checkpoint, "exit" won't work, so I just kill the
  # child gnuplot process
  if( defined $this->{pid})
  {
    if( $this->{checkpoint_stuck} )
    {
      kill 'TERM', $this->{pid};
    }
    else
    {
      _printGnuplotPipe( $this, "exit\n" );
    }

    waitpid( $this->{pid}, 0 ) ;
  }
}

# the main API function to generate a plot. Input arguments are a bunch of
# piddles optionally preceded by a bunch of options for each curve. See the POD
# for details
sub plot
{
  barf( "Plot called with no arguments") unless @_;

  my $this;

  if(defined ref $_[0] && ref $_[0] eq 'PDL::Graphics::Gnuplot')
  {
    # I called this as an object-oriented method. First argument is the
    # object. I already got the plot options in the constructor, so I don't need
    # to get them again.
    $this = shift;
  }
  else
  {
    # plot() called as a global function, NOT as a method. The initial arguments
    # can be the plot options (hashrefs or inline). I keep trying to parse the
    # initial arguments as plot options until I run out
    my $plotOptions = {};

    while(1)
    {
      if (defined ref $_[0] && ref $_[0] eq 'HASH')
      {
        # arg is a hash. Is it plot options or curve options?
        my $NmatchedPlotOptions = grep {defined $plotOptionsSet{$_}} keys %{$_[0]};

        last if $NmatchedPlotOptions == 0; # not plot options, so done scanning

        if( $NmatchedPlotOptions != scalar keys %{$_[0]} )
        { barf "Plot option hash has some non-plot options"; }

        # grab all the plot options
        my $newPlotOptions = shift;
        foreach my $key (keys %$newPlotOptions)
        { $plotOptions->{$key} = $newPlotOptions->{$key}; }
      }
      else
      {
        # arg is NOT a hashref. It could be an inline hash. I grab a hash pair
        # if it's plot options
        last unless @_ >= 2 && $plotOptionsSet{$_[0]};

        my $key = shift;
        my $val = shift;
        $plotOptions->{$key} = $val;
      }
    }

    $this = $globalPlot = PDL::Graphics::Gnuplot->new($plotOptions);
  }

  my $plotOptions = $this->{options};

  # I split my data-to-plot into similarly-styled chunks
  # pieces of data we're plotting. Each chunk has a similar style
  my ($chunks, $Ncurves) = parseArgs($plotOptions->{'3d'}, @_);


  if( scalar @$chunks == 0)
  { barf "plot() was not given any data"; }


  # I'm now ready to send the plot command. If the plot command fails, I'll get
  # an error message; if it succeeds, gnuplot will sit there waiting for data. I
  # don't want to have a timeout waiting for the error message, so I try to run
  # the plot command to see if it works. I make a dummy plot into the 'dumb'
  # terminal, and then _checkpoint() for errors.  To make this quick, the test
  # plot command contains the minimum number of data points
  my ($plotcmd, $testplotcmd, $testplotdata) =
    plotcmd( $chunks, $plotOptions );

  testPlotcmd($this, $testplotcmd, $testplotdata);

  # tests ok. Now set the terminal and actually make the plot!
  if(defined $this->{options}{terminal})
  { _safelyWriteToPipe($this, "set terminal $this->{options}{terminal}\n", 'terminal'); }

  if(defined $this->{options}{output})
  { _safelyWriteToPipe($this, "set output \"$this->{options}{output}\"\n", 'output'); }

  # all done. make the plot
  _printGnuplotPipe( $this, "$plotcmd\n");

  foreach my $chunk(@$chunks)
  {
    # In order for the PDL threading to work, I need at least one dimension. Add
    # it where needed. pdl(5) has 0 dimensions, for instance. I really want
    # something like "plot(5, pdl(3,4,5,3,4))" to work; It doesn't right
    # now. This map() makes "plot(pdl(3), pdl(5))" work. This is good for
    # completeness, but not really all that interesting
    my @data = map {$_->ndims == 0 ? $_->dummy(0) : $_} @{$chunk->{data}};

    my $tuplesize = scalar @data;
    eval( "_writedata_$tuplesize" . '(@data, $this, $plotOptions->{binary})');
  }

  # read and report any warnings that happened during the plot
  _checkpoint($this, 'printwarnings');







  # generates the gnuplot command to generate the plot. The curve options are parsed here
  sub plotcmd
  {
    my ($chunks, $plotOptions) = @_;

    my $basecmd = '';

    # if anything is to be plotted on the y2 axis, set it up
    if( grep {my $chunk = $_; grep {$_->{y2}} @{$chunk->{options}}} @$chunks)
    {
      if ( $plotOptions->{'3d'} )
      { barf "3d plots don't have a y2 axis"; }

      $basecmd .= "set ytics nomirror\n";
      $basecmd .= "set y2tics\n";
    }

    if($plotOptions->{'3d'} ) { $basecmd .= 'splot '; }
    else                      { $basecmd .= 'plot ' ; }


    my @plotChunkCmd;
    my @plotChunkCmdMinimal; # same as above, but with a single data point per plot only
    my $testData = '';       # data to make a minimal plot

    foreach my $chunk (@$chunks)
    {
      my @optionCmds =
        map { optioncmd($_, $plotOptions->{globalwith}) } @{$chunk->{options}};

      if( $plotOptions->{binary} )
      {
        # I get 2 formats: one real, and another to test the plot cmd, in case it
        # fails. The test command is the same, but with a minimal point count. I
        # also get the number of bytes in a single data point here
        my ($format, $formatMinimal) = binaryFormatcmd($chunk);
        my $Ntestbytes_here          = getNbytes_tuple($chunk);

        push @plotChunkCmd,        map { "'-' $format $_"     }    @optionCmds;
        push @plotChunkCmdMinimal, map { "'-' $formatMinimal $_" } @optionCmds;

        # If there was an error, these whitespace commands will simply do
        # nothing. If there was no error, these are data that will be plotted in
        # some manner. I'm not actually looking at this plot so I don't care
        # what it is. Note that I'm not making assumptions about how long a
        # newline is (perl docs say it could be 0 bytes). I'm printing as many
        # spaces as the number of bytes that I need, so I'm potentially doubling
        # or even tripling the amount of needed data. This is OK, since gnuplot
        # will simply ignore the tail.
        $testData .= " \n" x ($Ntestbytes_here * scalar @optionCmds);
      }
      else
      {
        # I'm using ascii to talk to gnuplot, so the minimal and "normal" plot
        # commands are the same (point count is not in the plot command)
        push @plotChunkCmd, map { "'-' $_" } @optionCmds;

        my $testData_curve = $testdataunit_ascii x $chunk->{tuplesize} . "\n" . "e\n";
        $testData .= $testData_curve x scalar @optionCmds;
      }
    }

    # the command to make the plot and to test the plot
    my $cmd        = $basecmd . join(',', @plotChunkCmd);
    my $cmdMinimal = @plotChunkCmdMinimal ?
      $basecmd . join(',', @plotChunkCmdMinimal) :
      $cmd;

    return ($cmd, $cmdMinimal, $testData);



    # parses a curve option
    sub optioncmd
    {
      my $option     = shift;
      my $globalwith = shift;

      my $cmd = '';

      if( defined $option->{legend} )
      { $cmd .= "title \"$option->{legend}\" "; }
      else
      { $cmd .= "notitle "; }

      # use the given per-curve 'with' style if there is one. Otherwise fall
      # back on the global
      my $with = $option->{with} || $globalwith;

      $cmd .= "with $with " if $with;
      $cmd .= "axes x1y2 "  if $option->{y2};

      return $cmd;
    }

    sub binaryFormatcmd
    {
      # I make 2 formats: one real, and another to test the plot cmd, in case it
      # fails
      my $chunk = shift;

      my $tuplesize  = $chunk->{tuplesize};
      my $recordSize = $chunk->{data}[0]->dim(0);

      my $format = "binary record=$recordSize format=\"";
      $format .= '%double' x $tuplesize;
      $format .= '"';

      # When plotting in binary, gnuplot gets confused if I don't explicitly
      # tell it the tuplesize. It's got its own implicit-tuples logic that I
      # don't want kicking in. As an example, the following simple plot doesn't
      # work in binary without this extra line:
      # plot3d(binary => 1,
      #        with => 'image', sequence(5,5));
      $format .= ' using ' . join(':', 1..$tuplesize);

      # to test the plot I plot a single record
      my $formatTest = $format;
      $formatTest =~ s/record=\d+/record=1/;

      return ($format, $formatTest);
    }

    sub getNbytes_tuple
    {
      my $chunk = shift;
      # assuming sizeof(double)==8
      return 8 * $chunk->{tuplesize};
    }
  }

  sub parseArgs
  {
    # Here I parse the plot() arguments.  Each chunk of data to plot appears in
    # the argument list as plot(options, options, ..., data, data, ....). The
    # options are a hashref, an inline hash or can be absent entirely. THE
    # OPTIONS ARE ALWAYS CUMULATIVELY DEFINED ON TOP OF THE PREVIOUS SET OF
    # OPTIONS (except the legend)
    # The data arguments are one-argument-per-tuple-element.
    my $is3d = shift;
    my @args = @_;

    # options are cumulative except the legend (don't want multiple plots named
    # the same). This is a hashref that contains the accumulator
    my $lastOptions = {};

    my @chunks;
    my $Ncurves  = 0;
    my $argIndex = 0;
    while($argIndex <= $#args)
    {
      # First, I find and parse the options in this chunk
      my $nextDataIdx = first {ref $args[$_] && ref $args[$_] eq 'PDL'} $argIndex..$#args;
      last if !defined $nextDataIdx; # no more data. done.

      # I do not reuse the curve legend, since this would result it multiple
      # curves with the same name
      delete $lastOptions->{legend};

      my %chunk;
      if( $nextDataIdx > $argIndex )
      {
        $chunk{options} = parseOptionsArgs($lastOptions, @args[$argIndex..$nextDataIdx-1]);

        # make sure I know what to do with all the options
        foreach my $option (@{$chunk{options}})
        {
          if (my @badKeys = grep {!defined $curveOptionsSet{$_}} keys %$option)
          {
            barf "plot() got some unknown curve options: (@badKeys)";
          }
        }
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

      my $tuplesize    = getTupleSize($is3d, $chunk{options});
      my $NdataPiddles = $nextOptionIdx - $argIndex;

      # If I have more data piddles that I need, use only what I need now, and
      # use the rest for the next curve
      if($NdataPiddles > $tuplesize)
      {
        $nextOptionIdx = $argIndex + $tuplesize;
        $NdataPiddles  = $tuplesize;
      }

      my @dataPiddles   = @args[$argIndex..$nextOptionIdx-1];

      if($NdataPiddles < $tuplesize)
      {
        # I got fewer data elements than I expected

        if(!$is3d && $NdataPiddles+1 == $tuplesize)
        {
          # A 2D plot is one data element short. Fill in a sequential domain
          # 0,1,2,...
          unshift @dataPiddles, sequence($dataPiddles[0]->dim(0));
        }
        elsif($is3d && $NdataPiddles+2 == $tuplesize)
        {
          # a 3D plot is 2 elements short. Use a grid as a domain
          my @dims = $dataPiddles[0]->dims();
          if(@dims < 1)
          { barf "plot() tried to build a 2D implicit domain, but the first data piddle is too small"; }

          # grab the first 2 dimensions to build the x-y domain
          splice @dims, 2;
          my $x = zeros(@dims)->xvals->clump(2);
          my $y = zeros(@dims)->yvals->clump(2);
          unshift @dataPiddles, $x, $y;

          # un-grid the data-to plot to match the new domain
          foreach my $data(@dataPiddles)
          { $data = $data->clump(2); }
        }
        else
        { barf "plot() needed $tuplesize data piddles, but only got $NdataPiddles"; }
      }

      $chunk{data}      = \@dataPiddles;
      $chunk{tuplesize} = $tuplesize;
      $chunk{Ncurves}   = countCurvesAndValidate(\%chunk);
      $Ncurves += $chunk{Ncurves};

      push @chunks, \%chunk;

      $argIndex = $nextOptionIdx;
    }

    return (\@chunks, $Ncurves);




    sub parseOptionsArgs
    {
      # my options are cumulative, except the legend. This variable contains the accumulator
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

            # I do not reuse the curve legend, since this would result it multiple
            # curves with the same name
            delete $options->{legend};
          }
          else
          {
            barf "plot() got a reference to a " . ref( $optionArg) . ". I can only deal with HASHes and ARRAYs";
          }

          $optionArgIdx++;
        }
        else
        {
          my %unrefedOptions;
          do
          {
            $optionArg = $optionsArgs[$optionArgIdx];

            # this is a scalar. I interpret a pair as key/value
            if ($optionArgIdx+1 == @optionsArgs)
            { barf "plot() got a lone scalar argument $optionArg, where a key/value was expected"; }

            $options->{$optionArg} = $optionsArgs[++$optionArgIdx];
            $optionArgIdx++;
          } while($optionArgIdx < @optionsArgs && !ref $optionsArgs[$optionArgIdx]);
          push @curveOptions, dclone($options);

          # I do not reuse the curve legend, since this would result it multiple
          # curves with the same name
          delete $options->{legend};
        }

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

      # I now make sure I have exactly one set of curve options per curve
      my $Ncurves = countCurves($data);
      my $Noptions = scalar @{$chunk->{options}};

      if($Noptions > $Ncurves)
      { barf "plot() got $Noptions options but only $Ncurves curves. Not enough curves"; }
      elsif($Noptions < $Ncurves)
      {
        # I have more curves then options. I pad the option list with the last
        # option, removing the legend
        my $lastOption = dclone $chunk->{options}[-1];
        delete $lastOption->{legend};
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
              if(defined $nonDegenerateDim && $nonDegenerateDim != $dim)
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
      my $is3d    = shift;
      my $options = shift;

      # I have a list of options for a set of curves in a chunk. Inside a chunk
      # the tuple set MUST be the same. I.e. I can have 2d data in one chunk and
      # 3d data in another, but inside a chunk it MUST be consistent
      my $size;
      foreach my $option (@$options)
      {
        my $sizehere;

        if ($option->{tuplesize})
        {
          # if we have a given tuple size, just use it
          $sizehere = $option->{tuplesize};
        }
        else
        {
          $sizehere = $is3d ? 3 : 2; # given nothing else, use ONLY the geometrical plotting
        }

        if(!defined $size)
        { $size = $sizehere;}
        else
        {
          if($size != $sizehere)
          {
            barf "plot() tried to change tuplesize in a chunk: $size vs $sizehere";
          }
        }
      }

      return $size;
    }
  }

  sub testPlotcmd
  {
    # I test the plot command by making a dummy plot with the test command.
    my ($this, $testplotcmd, $testplotdata) = @_;

    _printGnuplotPipe( $this, "set terminal push\n" );
    _printGnuplotPipe( $this, "set output\n" );
    _printGnuplotPipe( $this, "set terminal dumb\n" );

    # I send a test plot command. Gnuplot implicitly uses && if multiple
    # commands are present on the same line. Thus if I see the post-plot print
    # in the output, I know the plot command succeeded
    _printGnuplotPipe( $this, $testplotcmd . "\n" );
    _printGnuplotPipe( $this, $testplotdata );

    my $checkpointMessage = _checkpoint($this, 'ignore_known_test_failures');

    if( $checkpointMessage )
    {
      # There's a checkpoint message. I explicitly ignored and threw away all
      # errors that are allowed to occur during a test. Anything leftover
      # implies a plot failure.
      barf "Gnuplot error: \"\n$checkpointMessage\n\" while sending plotcmd \"$testplotcmd\"";
    }

    _printGnuplotPipe( $this, "set terminal pop\n" );
  }

  # syncronizes the child and parent processes. After _checkpoint() returns, I
  # know that I've read all the data from the child. Extra data that represents
  # errors is returned. Warnings are explicitly stripped out
  sub _checkpoint
  {
    my $this   = shift;
    my $pipeerr = $this->{err};

    # string containing various options to this function
    my $flags = shift;

    # I have no way of knowing if the child process has sent its error data
    # yet. It may be that an error has already occurred, but the message hasn't
    # yet arrived. I thus print out a checkpoint message and keep reading the
    # child's STDERR pipe until I get that message back. Any errors would have
    # been printed before this
    my $checkpoint = "xxxxxxx Syncronizing gnuplot i/o xxxxxxx";

    _printGnuplotPipe( $this, "print \"$checkpoint\"\n" );


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

      _logEvent($this, "Trying to read from gnuplot");

      if( $this->{errSelector}->can_read(5) )
      {
        # read a byte into the tail of $fromerr. I'd like to read "as many bytes
        # as are available", but I don't know how to this in a very portable way
        # (I just know there will be windows users complaining if I simply do a
        # non-blocking read). Very little data will be coming in anyway, so
        # doing this a byte at a time is an irrelevant inefficiency
        my $byte;
        sysread $pipeerr, $byte, 1;
        $fromerr .= $byte;

        _logEvent($this, "Read byte '$byte' (0x" . unpack("H2", $byte) . ") from gnuplot child process");
      }
      else
      {
        _logEvent($this, "Gnuplot read timed out");

        $this->{checkpoint_stuck} = 1;

        barf <<EOM;
Gnuplot process no longer responding. This is likely a bug in PDL::Graphics::Gnuplot
and/or gnuplot itself. Please report this as a PDL::Graphics::Gnuplot bug.
EOM
      }
    } until $fromerr =~ /\s*(.*?)\s*$checkpoint.*$/ms;

    $fromerr = $1;

    my $warningre = qr{^.*(?:warning:\s*(.*?)\s*$)\n?}mi;

    if(defined $flags && $flags =~ /printwarnings/)
    {
      while($fromerr =~ m/$warningre/gm)
      { print STDERR "Gnuplot warning: $1\n"; }
    }


    # I've now read all the data up-to the checkpoint. Strip out all the warnings
    $fromerr =~ s/$warningre//gm;

    # if asked, ignore and get rid of all the errors known to happen during
    # plot-command testing. These include
    #
    # 1. "invalid command" errors caused by the test data bein sent to gnuplot
    #    as a command. The plot command itself will never be invalid, so this
    #    doesn't actually mask out any errors
    #
    # 2. "invalid range" errors caused by requested plot bounds (xmin, xmax,
    #    etc) tossing out any test-plot data. The point of the plot-command
    #    testing is to make sure the command is valid, so any out-of-boundedness
    #    of the test data is irrelevant
    if(defined $flags && $flags =~ /ignore_known_test_failures/)
    {
      $fromerr =~ s/^gnuplot>\s*(?:$testdataunit_ascii|e\b).*$ # report of the actual invalid command
                    \n^\s+\^\s*$                               # ^ mark pointing to where the error happened
                    \n^.*invalid\s+command.*$//xmg;            # actual 'invalid command' complaint


      # ignore a simple 'invalid range' error observed when, say only the xmin
      # bound is set and all the data is below it
      $fromerr =~ s/^gnuplot>\s*plot.*$                        # the test plot command
                    \n^\s+\^\s*$                               # ^ mark pointing to where the error happened
                    \n^.*range\s*is\s*invalid.*$//xmg;         # actual 'invalid range' complaint

      # fancier plots show a different 'invalid range' error. Observed when xmin
      # > xmax (inverted x axis) and when there's out-of-bounds data
      $fromerr =~ s/^gnuplot>\s*plot.*$                        # the test plot command
                    \n^\s+\^\s*$                               # ^ mark pointing to where the error happened
                    \n^.*all\s*points.*undefined.*$//xmg;      # actual 'invalid range' complaint
    }

    $fromerr =~ s/^\s*(.*?)\s*/$1/;

    return $fromerr;
  }
}

# these are convenience wrappers for plot()
sub plot3d
{
  plot('3d' => 1, @_);
}

sub plotlines
{
  plot(globalwith => 'lines', @_);
}

sub plotpoints
{
  plot(globalwith => 'points', @_);
}


# subroutine to write the columns of some piddles into a gnuplot stream. This
# assumes the last argument is a file handle. Generally you should NOT be using
# this directly at all; it's just used to define the threading-aware routines
sub _wcols_gnuplot
{
  my $isbinary = pop @_;
  my $this     = pop @_;

  if( $isbinary)
  {
    # this is not efficient right now. I should do this in C so that I don't
    # have to physical-ize the piddles and so that I can keep the original type
    # instead of converting to double
    _printGnuplotPipe( $this, ${ cat(@_)->transpose->double->get_dataref } );
  }
  else
  {
    _wcolsGnuplotPipe( $this, @_ );
    _printGnuplotPipe( $this, "e\n" );
  }
};


sub _printGnuplotPipe
{
  my $this   = shift;
  my $string = shift;

  my $pipein = $this->{in};
  print $pipein $string;

  my $len = length $string;
  _logEvent($this,
            "Sent to child process $len bytes ==========\n" . $string . "\n=========================" );
}

sub _wcolsGnuplotPipe
{
  my $this   = shift;

  my $pipein = $this->{in};
  wcols @_, $pipein;

  if( $this->{options}{log} )
  {
    my $string;
    open FH, '>', \$string or barf "Couldn't open filehandle into string";
    wcols @_, *FH;
    close FH;

    _logEvent($this,
              "Sent to child process ==========\n" . $string . "\n=========================" );
  }
}

sub _safelyWriteToPipe
{
  my ($this, $string, $flags) = @_;

  foreach my $line(split('\s*?\n+\s*?', $string))
  {
    next unless $line;

    barfOnDisallowedCommands($line, $flags);

    _printGnuplotPipe( $this, "$line\n" );

    if( my $errorMessage = _checkpoint($this, 'printwarnings') )
    {
      barf "Gnuplot error: \"\n$errorMessage\n\" while sending line \"$line\"";
    }
  }

  sub barfOnDisallowedCommands
  {
    my $line  = shift;
    my $flags = shift;

    # I use STDERR as the backchannel, so I don't allow any "set print"
    # commands, since those can disable that
    if ( $line =~ /^(?: .*;)?       # optionally wait for a semicolon
                   \s*
                   set\s+print\b/x )
    {
      barf "Please don't 'set print' since I use gnuplot's STDERR for error detection";
    }

    if ( $line =~ /^(?: .*;)?       # optionally wait for a semicolon
                   \s*
                   print\b/x )
    {
      barf "Please don't ask gnuplot to 'print' anything since this can confuse my error detection";
    }

    if ( $line =~ /^(?: .*;)?       # optionally wait for a semicolon
                   \s*
                   set\s+terminal\b/x )
    {
      if( !defined $flags || $flags !~ /terminal/ )
      {
        barf "Please do not 'set terminal' manually. Use the 'terminal' plot option instead";
      }
    }

    if ( $line =~ /^(?: .*;)?       # optionally wait for a semicolon
                   \s*
                   set\s+output\b/x )
    {
      if( !defined $flags || $flags !~ /output/ )
      {
        barf "Please do not 'set output' manually. Use the 'output' plot option instead";
      }
    }
  }
}

# I generate a bunch of PDL definitions such as
# _writedata_2(x1(n), x2(n)), NOtherPars => 2
# The last 2 arguments are (pipe, isbinary)
# 20 tuples per point sounds like plenty. The most complicated plots Gnuplot can
# handle probably max out at 5 or so
for my $n (2..20)
{
  my $def = "_writedata_$n(" . join( ';', map {"x$_(n)"} 1..$n) . "), NOtherPars => 2";
  thread_define $def, over \&_wcols_gnuplot;
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

  return unless $this->{options}{log}; # only log when asked

  my $t1 = tv_interval( $this->{t0}, [gettimeofday] );

  # $event can have '%', so I don't printf it
  my $logline = sprintf "==== PDL::Graphics::Gnuplot PID $this->{pid} at t=%.4f:", $t1;
  print STDERR "$logline $event\n";
}

1;


__END__


=head1 NAME

PDL::Graphics::Gnuplot - Gnuplot-based plotter for PDL

=head1 SYNOPSIS

 use PDL::Graphics::Gnuplot qw(plot plot3d);

 my $x = sequence(101) - 50;
 plot($x**2);

 plot( title => 'Parabola with error bars',
       with => 'xyerrorbars', tuplesize => 4, legend => 'Parabola',
       $x**2 * 10, abs($x)/10, abs($x)*5 );

 my $xy = zeros(21,21)->ndcoords - pdl(10,10);
 my $z = inner($xy, $xy);
 plot(title  => 'Heat map', '3d' => 1,
      extracmds => 'set view 0,0',
      with => 'image', tuplesize => 3, $z*2);

 my $pi    = 3.14159;
 my $theta = zeros(200)->xlinvals(0, 6*$pi);
 my $z     = zeros(200)->xlinvals(0, 5);
 plot3d(cos($theta), sin($theta), $z);


=head1 DESCRIPTION

This module allows PDL data to be plotted using Gnuplot as a backend. As much as
was possible, this module acts as a passive pass-through to Gnuplot, thus making
available the full power and flexibility of the Gnuplot backend. Gnuplot is
described in great detail at its upstream website: L<http://www.gnuplot.info>.

The main subroutine that C<PDL::Graphics::Gnuplot> exports is C<plot()>. A call
to C<plot()> looks like

 plot(plot_options,
      curve_options, data, data, ... ,
      curve_options, data, data, ... );

=head2 Options arguments

Each set of options is a hash that can be passed inline or as a hashref: both
C<plot( title =E<gt> 'Fancy plot!', ... )> and C<plot( {title =E<gt> 'Another fancy
plot'}, ...)> work. The plot options I<must> precede all the curve options.

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

 plot( with => 'points', $x, $a,
       y2   => 1,        $x, $b,
       with => 'lines',  $x, $c );

This plots 3 curves: $a vs. $x plotted with points on the main y-axis (this is
the default), $b vs. $x plotted with points on the secondary y axis, and $c
vs. $x plotted with lines also on the secondary y axis. All the curve options
are described below in L</"Curve options">.

=head2 Data arguments

Following the curve options in the C<plot()> argument list is the actual data
being plotted. Each output data point is a tuple whose size varies depending on
what is being plotted. For example if we're making a simple 2D x-y plot, each
tuple has 2 values; if we're making a 3d plot with each point having variable
size and color, each tuple has 5 values (x,y,z,size,color). In the C<plot()>
argument list each tuple element must be passed separately. If we're making
anything fancier than a simple 2D or 3D plot (2- and 3- tuples respectively)
then the C<tuplesize> curve option I<must> be passed in. Furthermore, PDL
threading is active, so multiple curves can be plotted by stacking data inside
the passed-in piddles. When doing this, multiple sets of curve options can be
passed in as multiple hashrefs preceding the data itself in the argument
list. By using hashrefs we can make clear which option corresponds to which
plot. An example:

 my $pi    = 3.14159;
 my $theta = zeros(200)->xlinvals(0, 6*$pi);
 my $z     = zeros(200)->xlinvals(0, 5);

 plot( '3d' => 1, title => 'double helix',

       { with => 'points pointsize variable pointtype 7 palette', tuplesize => 5,
         legend => 'spiral 1' },
       { legend => 'spiral 2' },

       # 2 sets of x, 2 sets of y, single z
       PDL::cat( cos($theta), -cos($theta)),
       PDL::cat( sin($theta), -sin($theta)),
       $z,

       # pointsize, color
       0.5 + abs(cos($theta)), sin(2*$theta) );

This is a 3d plot with variable size and color. There are 5 values in the tuple,
which we specify. The first 2 piddles have dimensions (N,2); all the other
piddles have a single dimension. Thus the PDL threading generates 2 distinct
curves, with varying values for x,y and identical values for everything else. To
label the curves differently, 2 different sets of curve options are given. Since
the curve options are cumulative, the style and tuplesize needs only to be
passed in for the first curve; the second curve inherits those options.


=head3 Implicit domains

When a particular tuplesize is specified, PDL::Graphics::Gnuplot will attempt to
read that many piddles. If there aren't enough piddles available,
PDL::Graphics::Gnuplot will throw an error, unless an implicit domain can be
used. This happens if we are I<exactly> 1 piddle short when plotting in 2D or 2
piddles short when plotting in 3D.

When making a simple 2D plot, if exactly 1 dimension is missing,
PDL::Graphics::Gnuplot will use C<sequence(N)> as the domain. This is why code
like C<plot(pdl(1,5,3,4,4) )> works. Only one piddle is given here, but a
default tuplesize of 2 is active, and we are thus exactly 1 piddle short. This
is thus equivalent to C<plot( sequence(5), pdl(1,5,3,4,4) )>.

If plotting in 3d, an implicit domain will be used if we are exactly 2 piddles
short. In this case, PDL::Graphics::Gnuplot will use a 2D grid as a
domain. Example:

 my $xy = zeros(21,21)->ndcoords - pdl(10,10);
 plot('3d' => 1,
       with => 'points', inner($xy, $xy));

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

Note that the C<tuplesize> curve option is independent of implicit domains. This
option specifies not how many data piddles we have, but how many values
represent each data point. For example, if we want a 2D plot with varying colors
plotted with an implicit domain, set C<tuplesize> to 3 as before, but pass in
only 2 piddles (y, color).

=head2 Interactivity

The graphical backends of Gnuplot are interactive, allowing the user to pan,
zoom, rotate and measure the data in the plot window. See the Gnuplot
documentation for details about how to do this. Some terminals (such as wxt) are
persistently interactive, and the rest of this section does not apply to
them. Other terminals (such as x11) have the downside described here.

When using an affected terminal, interactivity is only possible if the gnuplot
process is running. As long as the perl program calling PDL::Graphics::Gnuplot
is running, the plots are interactive, but once it exits, the child gnuplot
process will exit also. This will keep the plot windows up, but the
interactivity will be lost. So if the perl program makes a plot and exits, the
plot will NOT be interactive.

Due to particulars of the current implementation of PDL::Graphics::Gnuplot, each
time C<plot()> is called, a new gnuplot process is launched, killing the
previous one. This results only in the latest plot being interactive. The way to
resolve this is to use the object-oriented interface to PDL::Graphics::Gnuplot
(see L</"CONSTRUCTORS"> below).


=head1 OPTIONS

=head2 Plot options

The plot options are a hash, passed as the initial arguments to the global
C<plot()> subroutine or as the only arguments to the PDL::Graphics::Gnuplot
contructor. The supported keys of this hash are as follows:

=over 2

=item title

Specifies the title of the plot

=item 3d

If true, a 3D plot is constructed. This changes the default tuple size from 2 to
3

=item nogrid

By default a grid is drawn on the plot. If this option is true, this is turned off

=item globalwith

If no valid 'with' curve option is given, use this as a default

=item square, square_xy

If true, these request a square aspect ratio. For 3D plots, square_xy plots with
a square aspect ratio in x and y, but scales z. Using either of these in 3D
requires Gnuplot >= 4.4

=item xmin, xmax, ymin, ymax, zmin, zmax, y2min, y2max, cbmin, cbmax

If given, these set the extents of the plot window for the requested axes. The
y2 axis is the secondary y-axis that is enabled by the 'y2' curve option. The
'cb' axis represents the color axis, used when color-coded plots are being
generated

=item xlabel, ylabel, zlabel, y2label

These specify axis labels

=item hardcopy

Instead of drawing a plot on screen, plot into a file instead. The output
filename is the value associated with this key. The output format is inferred
from the filename. Currently only eps, ps, pdf, png are supported with some
default sets of options. This option is simply a shorthand for the C<terminal>
and C<output> options. If the defaults provided by the C<hardcopy> option are
insufficient, use C<terminal> and C<output> manually.

=item terminal

Sets the gnuplot terminal (with the gnuplot C<set terminal> command). This
determines what kind of output Gnuplot generates. See the Gnuplot docs for all
the details.

=item output

Sets the plot output file (with the gnuplot C<set output> command). You
generally only need to set this if you're generating a hardcopy, such as a PDF.

=item extracmds

Arbitrary extra commands to pass to gnuplot before the plots are created. These
are passed directly to gnuplot, without any validation. The value is either a
string of an arrayref of different commands

=item dump

Used for debugging. If true, writes out the gnuplot commands to STDOUT
I<instead> of writing to a gnuplot process. Useful to see what commands would be
sent to gnuplot. This is a dry run. Note that this dump will contain binary
data, if the 'binary' option is given (see below)

=item log

Used for debugging. If true, writes out the gnuplot commands to STDERR I<in
addition> to writing to a gnuplot process. This is I<not> a dry run: data is
sent to gnuplot I<and> to the log. Useful for debugging I/O issues. Note that
this log will contain binary data, if the 'binary' option is given (see below)

=item binary

If given, binary data is passed to gnuplot instead of ASCII data. Binary is much
more efficient (and thus faster). Binary input works for most plots, but not for
all of them. An example where binary plotting doesn't work is 'with labels'.
ASCII plotting is generally better tested so ASCII is the default. This will
change at some point in the near future

=back


=head2 Curve options

The curve options describe details of specific curves. They are in a hash, whose
keys are as follows:

=over 2

=item legend

Specifies the legend label for this curve

=item with

Specifies the style for this curve. The value is passed to gnuplot using its
'with' keyword, so valid values are whatever gnuplot supports. Read the gnuplot
documentation for the 'with' keyword for more information

=item y2

If true, requests that this curve be plotted on the y2 axis instead of the main y axis

=item tuplesize

Specifies how many values represent each data point. For 2D plots this defaults
to 2; for 3D plots this defaults to 3.

=back

=head1 FUNCTIONS

=head2 plot

=for ref

The main plotting routine in PDL::Graphics::Gnuplot.

Each C<plot()> call creates a new plot in a new window.

=for usage

 plot(plot_options,
      curve_options, data, data, ... ,
      curve_options, data, data, ... );

Most of the arguments are optional.

=for example

 use PDL::Graphics::Gnuplot qw(plot);
 my $x = sequence(101) - 50;
 plot($x**2);

See main POD for PDL::Graphics::Gnuplot for details.


=head2 plot3d

=for ref

Generates 3D plots. Shorthand for C<plot('3d' =E<gt> 1, ...)>

=head2 plotlines

=for ref

Generates plots with lines, by default. Shorthand for C<plot(globalwith =E<gt> 'lines', ...)>

=head2 plotpoints

=for ref

Generates plots with points, by default. Shorthand for C<plot(globalwith =E<gt> 'points', ...)>


=head1 CONSTRUCTORS

=head2 new

=for ref

Creates a PDL::Graphics::Gnuplot object to make a persistent plot.

=for example

  my $plot = PDL::Graphics::Gnuplot->new(title => 'Object-oriented plot');
  $plot->plot( legend => 'curve', sequence(5) );

The plot options are passed into the constructor; the curve options and the data
are passed into the method. One advantage of making plots this way is that
there's a gnuplot process associated with each PDL::Graphics::Gnuplot instance,
so as long as C<$plot> exists, the plot will be interactive. Also, calling
C<$plot-E<gt>plot()> multiple times reuses the plot window instead of creating a
new one.



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

         { with => 'points pointsize variable pointtype 7 palette', tuplesize => 5,
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



=head1 COMPATIBILITY

Everything should work on all platforms that support Gnuplot and Perl. That
said, I<ONLY> Debian GNU/Linux has been tested to work. Please report successes
or failures on other platforms to the author. A transcript of a failed run with
{log => 1} would be most helpful.

=head1 REPOSITORY

L<https://github.com/dkogan/PDL-Graphics-Gnuplot>

=head1 AUTHOR

Dima Kogan, C<< <dima@secretsauce.net> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Dima Kogan.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

