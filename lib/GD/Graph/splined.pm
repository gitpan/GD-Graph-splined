package GD::Graph::splined;

use vars '$VERSOIN';
$VERSION = "0.021";

use strict;
use warnings;

use Carp;
use GD::Graph::axestype;
use GD::Graph::area;			# v1.16
use GD::Polyline;

@GD::Graph::splined::ISA = qw(
	GD::Graph::axestype
	GD::Graph::area
);

# PRIVATE
sub draw_data_set {
    my $self = shift;       # object reference
    my $ds   = shift;       # number of the data set

	$self->{bez_segs} ||= 20;	# number of bezier segs -- number of segments in each portion of the spline produces by toSpline()
	$self->{csr} ||= 1/5;		# control seg ratio -- the one possibly user-tunable parameter in the addControlPoints() algorithm

    my @values = $self->{_data}->y_values($ds) or
        return $self->_set_error("Impossible illegal data set: $ds",
            $self->{_data}->error);

    # Select a data colour
    my $dsci = $self->set_clr($self->pick_data_clr($ds));

    # Create a new polygon
    my $poly = GD::Polyline->new();

    my @bottom;

    # Add the data points
    for (my $i = 0; $i < @values; $i++) {
        my $value = $values[$i];
        # Graph zeros so that addControlPoints doesn't barf
        $value = 0 unless defined $value;
        # next unless defined $value;

        my $bottom = $self->_get_bottom($ds, $i);
        $value = $self->{_data}->get_y_cumulative($ds, $i)
            if ($self->{overwrite} == 2);

        my ($x, $y) = $self->val_to_pixel($i + 1, $value, $ds);
        $poly->addPt($x, $y);

		# Need to keep track of this stuff for hotspots, and because
		# it's the only reliable way of closing the polygon, without
		# making odd assumptions.
        push @bottom, [$x, $bottom];

        # Hotspot stuff
        # XXX needs fixing. Not used at the moment.
		next unless defined $self->{_hotspots}->[$ds]->[$i];

        if ($i == 0) {
            $self->{_hotspots}->[$ds]->[$i] = ["poly",
                $x, $y,
                $x , $bottom,
                $x - 1, $bottom,
                $x - 1, $y,
                $x, $y];
        }
        else {
            $self->{_hotspots}->[$ds]->[$i] = ["poly",
                $poly->getPt($i),
                @{$bottom[$i]},
                @{$bottom[$i-1]},
                $poly->getPt($i-1),
                $poly->getPt($i)];
        }
    }

	if ($poly->vertices<=1){
		Carp::croak "Impossible dataset for a splined graph: too few vertices in polyline";
	}
	my $spline = $poly->addControlPoints(
		$self->{bez_segs},
		$self->{csr},
	)->toSpline;
	$self->{graph}->polydraw($spline,$dsci);

    # Draw the accent lines
    my $brci = $self->set_clr($self->pick_border_clr($ds));
    if (defined $brci and
       ($self->{right} - $self->{left})/@values > $self->{accent_treshold}
	) {
		for (my $i = 1; $i < @values - 1; $i++) {
			my $value = $values[$i];
			my ($x, $y) = $poly->getPt($i);
			my $bottom = $bottom[$i]->[1];
			$self->{graph}->dashedLine($x, $y, $x, $bottom, $brci);
        }
    }

    return $ds
}


#
# All this stuff
#

our $PI = 3.14159;
our $TWO_PI = 2 * $PI;
sub pi { $PI }

sub GD::Polyline::addControlPoints {
    my $self = shift;
    my $bezSegs = shift || 20;
    my $csr = shift || 1/5; # Orig default was 1/3

    my @points = $self->vertices();

	unless (@points > 1) {
	    carp "Attempt to call addControlPoints() with too few vertices in polyline";
		return undef;
	}

	my $points = scalar(@points);
	my @segAngles  = $self->segAngle();
	my @segLengths = $self->segLength();

	my ($prevLen, $nextLen, $prevAngle, $thisAngle, $nextAngle);
	my ($controlSeg, $pt, $ptX, $ptY, @controlSegs);

	# this loop goes about creating polylines -- here called control segments --
	# that hold the control points for the final set of control points

	# each control segment has three points, and these are colinear

	# the first and last will ultimately be "director points", and
	# the middle point will ultimately be an "anchor point"

	for my $i (0..$#points) {

		$controlSeg = new GD::Polyline;

		$pt = $points[$i];
		($ptX, $ptY) = @$pt;

		if ($self->isa('GD::Polyline') and ($i == 0 or $i == $#points)) {
			$controlSeg->addPt($ptX, $ptY);	# director point
			$controlSeg->addPt($ptX, $ptY);	# anchor point
			$controlSeg->addPt($ptX, $ptY);	# director point
			next;
		}

		$prevLen = $segLengths[$i-1];
		$nextLen = $segLengths[$i];
		$prevAngle = $segAngles[$i-1];
		$nextAngle = $segAngles[$i];

		# make a control segment with control points (director points)
		# before and after the point from the polyline (anchor point)

		$controlSeg->addPt($ptX - $csr * $prevLen, $ptY);	# director point
		$controlSeg->addPt($ptX                  , $ptY);	# anchor point
		$controlSeg->addPt($ptX + $csr * $nextLen, $ptY);	# director point

		# note that:
		# - the line is parallel to the x-axis, as the points have a common $ptY
		# - the points are thus clearly colinear
		# - the director point is a distance away from the anchor point in proportion to the length of the segment it faces

		# now, we must come up with a reasonable angle for the control seg
		#  first, "unwrap" $nextAngle w.r.t. $prevAngle
		$nextAngle -= 2*pi() until $nextAngle < $prevAngle + pi();
		$nextAngle += 2*pi() until $nextAngle > $prevAngle - pi();
		#  next, use seg lengths as an inverse weighted average
		#  to "tip" the control segment toward the *shorter* segment
		$thisAngle = ($nextAngle * $prevLen + $prevAngle * $nextLen) / ($prevLen + $nextLen);

		# rotate the control segment to $thisAngle about it's anchor point
		$controlSeg->rotate($thisAngle, $ptX, $ptY);

	} continue {
		# save the control segment for later
		push @controlSegs, $controlSeg;

	}

	# post process

	my $controlPoly = new GD::Polyline; # ref($self);

	# collect all the control segments' points in to a single control poly

	foreach my $cs (@controlSegs) {
		foreach my $pt ($cs->vertices()) {
			$controlPoly->addPt(@$pt);
		}
	}

	# final clean up based on poly type

	if ($controlPoly->isa('GD::Polyline')) {
		# remove the first and last control point
		# since they are director points ...
		$controlPoly->deletePt(0);
		$controlPoly->deletePt($controlPoly->length()-1);
	} else {
		# move the first control point to the last control point
		# since it is supposed to end with two director points ...
		$controlPoly->addPt($controlPoly->getPt(0));
		$controlPoly->deletePt(0);
	}

	return $controlPoly;
}

1;

__END__

=head1 NAME

GD::Graph::splined - Smooth line graphs with GD::Graph

=head1 SYNOPSIS

	use strict;
	use GD::Graph::splined;

	my @data = (
	    ["1st","2nd","3rd","4th","5th","6th","7th", "8th", "9th"],
	    [    5,   12,   24,   33,   19,undef,    6,    15,    21],
	    [    1,    2,    5,    6,    3,  1.5,    1,     3,     4]
	);

	my $graph = GD::Graph::splined->new;

	$graph->set(
		x_label => 'X Label',
		y_label => 'Y label',
		title => 'A Splined Graph',
	);
	$graph->set_legend( 'one', 'two' );
	$graph->plot(\@data);

	open(OUT, ">splined.png") or die $!;
	binmode OUT;
	print OUT $graph->gd->png;
	close OUT;

=head1 DESCRIPTION

A L<GD::Graph|GD::Graph> module that can be treated as an C<area> graph, but
renders splined (smoothed) line graphs.

If you find that the curves loop back over themselves, try setting the
field C<csr> (Control Segment Ratio) to a smaller fraction than the default C<1/5>. To smooth a curve
more, increase the value of the field.

See L<GD::Graph|GD::Graph> for more details of how to produce graphs with GD.

=head1 BUGS

Please use the CPAN Request Tracker to lodge bugs: L<http://rt.cpan.org|http://rt.cpan.org>.

=head1 SEE ALSO

L<GD::Graph>, L<GD::Graph::area>, L<GD::Polyline>, L<GD>.

=head1 AUTHOR AND COPYRIGHT

Lee Goddard added to Martien Verbruggen's L<GD::Graph::area|GD::Graph::area> module
the ability to use Daniel J Harasty's L<GD::Polyline> module.

Thus, Copyright (c) 1995-2000 Martien Verbruggen
with parts copyright (c) 2006 Lee Goddard (lgoddard -at- cpan -dot- org).

This software is made available under the same terms as L<GD::Graph|GD::Graph>.
