use Dancer2;
use Module::Runtime qw(use_module);

get '/' => sub { 
  use_module('RankBall')->new->full_HTML(sort => params->{sort}); 
};

dance;
