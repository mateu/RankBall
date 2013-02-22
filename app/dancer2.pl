use Dancer2;
use Module::Runtime qw(use_module);

hook before => sub {
  var ranker => use_module('RankBall')->new; 
};

get '/' => sub { 
  vars->{ranker}->full_HTML(sort => params->{sort}); 
};

dance;
