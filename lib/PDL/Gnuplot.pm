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

  my $this = {plotoptions => $plotoptions};
  bless($this, $classname);

  $this->{pipe} = startGnuplot() or barf "Couldn't start gnuplot backend";

  return $this;




  sub startGnuplot
  {
    my $pipe;
    unless( open $pipe, '|-', "gnuplot --persist" )
    {
      say STDERR "Couldn't launch gnuplot";
      return;
    }
    return $pipe;
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

  my $pipe = $this->{pipe};

  say $pipe plotcmd($N, $options);

  _plotxy_writedata(@_, $pipe);
  flush $pipe;


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

  sub plotcmd
  {
    my ($N, $options) = @_;

    $options //= [];

    # remove any options that exceed my data
    splice( @$options, $N ) if @$options > $N;

    # fill the options list to match the number of curves in length
    push @$options, ({}) x ($N - @$options);

    return 'plot ' . join(',', map {"'-' " . optioncmd($_)} @$options);


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
