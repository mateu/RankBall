package RankBall;
use Moo;
use WWW::Mechanize;
use HTML::TreeBuilder;
use HTML::TreeBuilder::Select;
use HTML::TableExtract;
use Data::Dumper::Concise;
use DDP colored => 0;

has mech => (
    is      => 'ro',
    lazy    => 1,
    default => sub { WWW::Mechanize->new },
);

sub get_pomeroy_ranks {
    my ($self,) = @_;

    my $url = 'http://kenpom.com';
    $self->mech->get($url);
    my $te = HTML::TableExtract->new(headers => [ 'Rank', 'Team', ],);
    $te->parse($self->mech->content);

    my %pomeroy_rank_for;
    foreach my $table ($te->tables) {
        foreach my $row ($table->rows) {
            my ($rank, $team) = @{$row}[0..1];
            next if (not ($team or $rank));
            # trim whitespace
            $team =~ s/\s*$//;
            $team = $self->canonicalize_team($team);
            $pomeroy_rank_for{$team} = $rank;
        }
    }
    return %pomeroy_rank_for;
}

sub get_sagarin_ranks {
    my ($self,) = @_;

    my $url = 'http://usatoday30.usatoday.com/sports/sagarin/bkt1213.htm';
    $self->mech->get($url);
    my $tree = HTML::TreeBuilder->new;
    $tree->parse_content($self->mech->content);
    my ($header, $data) = $tree->select("pre");
    my $text = $data->as_text;
    my @lines = split(/\n/, $text);
    my %sagarin_rank_for;
    foreach my $line (@lines) {

        # Do we have a rank line
        if (my ($rank, $team) = $line =~ m/^\s+(\d+)\s*([\w ]*)\s*=/) {

            # strip of trailing whitespace
            $team =~ s/\s*$//;
            $team = $self->canonicalize_team($team);
            $sagarin_rank_for{$team} = $rank;
        }
    }
    return %sagarin_rank_for;
}

sub get_ranks {
    my ($self, $poll) = @_;

    my %url_for = (
        'coaches' => 'http://www.usatoday.com/sports/ncaab/polls/coaches-poll',
        'ap'      => 'http://www.usatoday.com/sports/ncaab/polls/ap',
        'rpi'     => 'http://rivals.yahoo.com/ncaa/basketball/polls?poll=5',
    );
    $self->mech->get($url_for{$poll});
    my $te = HTML::TableExtract->new(headers => [ 'Rank', 'Team', ],);
    $te->parse($self->mech->content);

    my %rank_for;
    foreach my $table ($te->tables) {
        foreach my $row ($table->rows) {
            my ($rank, $team) = @{$row}[0..1];
            # Top 25 collected at this marker
            last if ($rank =~ m/Schools Dropped Out/);
            # remove &#160; 
            my $junk;
            ($junk, $team) = split(/\n/, $team) if ($poll eq 'coaches' or $poll eq 'ap');
            $team =~ s/\n//g;
            $team =~ s/\s*$//;
            $team =~ s/^\s*//;
            next if (not ($team or $rank));
            ($rank) = $rank =~ m/(\d+)/;
            die "row: ", Dumper $row if not $team;
            $team = $self->canonicalize_team($team);
            $rank_for{$team} = $rank;
        }
    }
    return %rank_for;
}

sub canonicalize_team {
  my ($self, $team) = @_;
  die "No team" if not $team;
  $team =~ s/St\./State/;
  $team =~ s/Miami-Florida/Miami FL/;
  $team =~ s/^Miami$/Miami FL/;
  $team =~ s/VCU\(Va. Commonwealth\)/Virginia Commonwealth/;
  return $team;
}

1
