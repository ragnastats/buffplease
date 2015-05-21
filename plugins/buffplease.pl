package OpenKore::Plugins::BuffPlease;

# Perl includes
use strict;
use Data::Dumper;
use Storable;

# Kore includes
use Settings;
use Plugins;
use Network;
use Globals;
use Match;
use Utils qw( min max timeOut parseArgs swrite formatNumber );
use Log qw( message warning error );
use Time::HiRes qw( time );

our $buff = {

    # This value is used to determine who will be buffed
    # 'all' buffs anyone who asks
    # 'guild' only buffs people in the following list of guilds
    'permission' => 'all',
    'guilds'     => [ 'RagnaStats', 'RagnaStats.com' ],

    # What qualifies as "please"?
    'please' => [ qw( please pwease pwese onegai ), 'por favor' ],

    # What qualifies as "plz"?
    'plz' => [ qw( plz pls plox ) ],

    # What qualifies as "more"?
    'more' => [ qw( more +1 again ) ],

    # Use this to map what skills are triggered by the chat
    'aliases' => {
        'Blessing'                 => '(?:all|full) buff|bless|buff',
        'Increase AGI'             => '(?:all|full) buff|\bagi\b|buff',
        'Sanctuary'                => 'sanc',
        'High Heal'                => 'high|highness|\bhh\b',
        'Ruwach'                   => 'sight',
        'Impositio Manus'          => '(?:all|full) buff|impo',
        'Kyrie Eleison'            => '\bKE\b|Kyrie|\bKy\b',
        'Resurrection'             => 'res\b|resu',
        'Status Recovery'          => '(?:all|full) buff|status|recovery',
        'Assumptio'                => '(?:all|full) buff|assu|buff',
        'Safety Wall'              => 'wall',
        'Magnificat'               => '\bmag\b|magni',
        'Secrament'                => '(?:all|full) buff|secra|sacra|sacrement',
        'Cantocandidus'            => 'canto',
        'Clementia'                => 'clem',
        'PRAEFATIO'                => 'prae',
        'Odins Power'              => 'odin',
        'Renovatio'                => '(?:all|full) buff|reno\b',
        'Full Chemical Protection' => 'fcp',
        'Endow Blaze'              => '(?:flame|fire) endow|endow (?:fire|flame)',
        'Endow Tsunami'            => '(?:ice|water) endow|endow (?:ice|water)',
        'Endow Tornado'            => 'wind endow|endow wind',
        'Endow Quake'              => '(?:earth|ground) endow|endow (?:earth|ground)',
        'Magic Strings'            => 'string|strings'
    },

    # These skills will never be used
    'ignore' => {
        'Teleport'        => 1,
        'Warp Portal'     => 1,
        'Classical Pluck' => 1,
    },

    # Messages to make fun of people who say plz
    'wit' => [
        "You mean please?",
        "Don't you mean please?",
        "You meant to say 'please', right?",
        "Please check your dictionary.",
        "Say please~",
        "Plz doesn't cut it.",
        "Pls isn't very polite.",
        "Just say please :3",
        "Please works better.",
        "lrn2spell",
        "P-l-e-a-s-e",
        "Just say please?",
        "This would be a lot easier if you said 'please'.",
        "Saying please goes a long way.",
        "Some day you'll learn... (to say please)",
        "Have you tried saying please?",
        "Where are your manners? Please try again.",
        "Say please first~",
        "Please please please!",
        "What's so hard about saying please?",
    ],
};

our $requests ||= [];
our $commands ||= [];
our $users    ||= {};
our $last_skill = '';
our $timeout = { time => 0, timeout => 0 };

my $please_regex = list_to_regex( @{ $buff->{please} } );
my $plz_regex    = list_to_regex( @{ $buff->{plz} } );
my $more_regex   = list_to_regex( @{ $buff->{more} } );

Plugins::register( "Buff Please?", "Buff people when they ask", \&unload );
my $hooks = Plugins::addHooks(
    [ 'mainLoop_post',               \&loop ],
    [ 'packet/skill_use_location',   \&skillUsed ],
    [ 'packet/skill_used_no_damage', \&skillUsed ],
    [ 'packet/actor_status_active',  \&parseStatus ],
    [ "packet_pubMsg",               \&parseChat ],
    [ "packet_partyMsg",             \&parseChat ],
    [ "packet_guildMsg",             \&parseChat ],
    [ "packet_selfChat",             \&parseChat ],
    [ "packet_privMsg",              \&parseChat ],
);

my $cmds = Commands::register(
    [
        buffplease => [    #
            'Auto-buff when people say please',
            [ list     => 'show buff queue' ],
            [ validate => 'validate plugin configuration' ]
        ],
        \&command,
    ]
);

Misc::configModify( buffPlease => 0 ) if !exists $config{buffPlease};

sub unload {
    Plugins::delHooks( $hooks );
    Commands::unregister( $cmds );
}

sub command {
    my ( undef, $args ) = @_;

    my ( $cmd, @args ) = parseArgs( $args );
    if ( $cmd eq 'list' ) {
        list();
    } elsif ( $cmd eq 'validate' ) {
        validate();
    } else {
        error "[buffplease] Unknown command.\n";
        Commands::helpIndent( 'buffplease', $Commands::customCommands{buffplease}{desc} );
    }
}

sub list {
    my $time = time;

    my $fmt = '[buffplease] @> @<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<< @>>>>>';

    my @lines;

    if ( @$requests ) {
        push @lines, "[buffplease] == Pending Requests ==========================\n";
        push @lines, swrite( $fmt, [ '', 'User', 'Skill', 'Amount' ] );
        my @sorted = sort { $a->{created_at} <=> $b->{created_at} } @$requests;
        foreach ( 0 .. $#sorted ) {
            my $req = $sorted[$_];
            my $amount = $req->{skill} == 28 && $users->{ $req->{target} }->{healFor} > 0 ? formatNumber( $users->{ $req->{target} }->{healFor} ) : '';
            push @lines, swrite( $fmt, [ $_, $req->{target}, Skill->new( idn => $req->{skill} )->getName, $amount ] );
        }
    } else {
        push @lines, "[buffplease] No pending requests.\n";
    }

    if ( @$commands ) {
        push @lines, "[buffplease] == Accepted Requests =========================\n";
        push @lines, swrite( $fmt, [ '', 'User', 'Skill', 'Amount' ] );
        foreach ( 0 .. $#$commands ) {
            my $req = $commands->[ $_ - 1 ];
            my $amount = $req->{skill} == 28 && $users->{ $req->{target} }->{healFor} > 0 ? formatNumber( $users->{ $req->{target} }->{healFor} ) : '';
            push @lines, swrite( $fmt, [ $_, $req->{target}, Skill->new( idn => $req->{skill} )->getName, $amount ] );
        }
    }

    message join '', @lines;
}

sub validate {
    my @errors;

    if ( !$config{buffPlease} ) {
        push @errors, "[buffplease] Not enabled. To enable: conf buffPlease 1\n";
    }

    # Validate aliases values. Do the regular expressions compile?
    foreach ( sort keys %{ $buff->{aliases} } ) {
        next if eval {qr{$buff->{aliases}->{$_}}};
        push @errors, "[buffplease] Alias key [$_] has an invalid regular expression.\n";
    }

    # Validate aliases and ignore keys. Do the skills actually exist?
    foreach ( sort keys %{ $buff->{aliases} } ) {
        next if Skill::lookupIDNByName( $_ );
        push @errors, "[buffplease] Alias key [$_] is not a valid skill name!\n";
    }
    foreach ( sort keys %{ $buff->{ignore} } ) {
        next if Skill::lookupIDNByName( $_ );
        push @errors, "[buffplease] Ignore key [$_] is not a valid skill name!\n";
    }

    # Validate permission. Valid values are "all" and "guild".
    my $valid_permissions = [qw( all guild )];
    if ( !in_array( $valid_permissions, $buff->{permission} ) ) {
        push @errors, "[buffplease] Permission [$buff->{permission}] is invalid. Valid permissions are: @$valid_permissions\n";
    }

    error join '', @errors if @errors;
    message "[buffplease] Validation complete. Found " . @errors . " errors.\n";
}

sub in_array {
    my ( $arr, $search_for ) = @_;
    foreach my $value ( @$arr ) {
        return 1 if $value eq $search_for;
    }
    return 0;
}

sub next_request {
    my $time = time;

    # Delete requests older than 30 seconds.
    @$requests = grep {
        if ( $time - $_->{created_at} > 30 ) {
            warning sprintf "[buffplease] Ignoring request to use skill [%s] on user [%s] because it is too old [%.1f seconds].\n", $_->{skill}, $_->{target}, $time - $_->{created_at};
            0;
        } else {
            1;
        }
    } @$requests;

    while ( @$commands or @$requests ) {
        if ( !@$commands ) {

            # User or target must have said "please" within 30 seconds to be acceptable.
            my @acceptable = grep { $time - $users->{ $_->{user} }->{pleased_at} < 30 or $time - $users->{ $_->{target} }->{pleased_at} < 30 } @$requests;

            # No commands and no acceptable requests, we're done.
            return if !@acceptable;

            # Order requests by the last time we fulfilled a request by that user, to make sure everybody gets a fair chance.
            @acceptable = sort { $users->{ $b->{target} }->{buffed_at} <=> $users->{ $a->{target} }->{buffed_at} || $a->{created_at} <=> $b->{created_at} } @acceptable;

            # Take the first request.
            my $req = shift @acceptable;
            @$requests = grep { $_ ne $req } @$requests;
            push @$commands, $req;
        }

        my $req = shift @$commands;
        message sprintf "[buffplease] Accepting request to use skill [%s] on user [%s] (last please was %.1f seconds ago).\n", $req->{skill}, $req->{target}, $time - $users->{ $req->{target} }->{pleased_at};
        return $req;
    }

    return;
}

# This is where we periodically loop through the requested commands.
sub loop {
    return if !$config{buffPlease};
    return if !timeOut( $timeout );

    # Check at most every 0.1 seconds.
    $timeout = { time => time, timeout => 0.1 };

    while ( my $req = next_request() and $char->statusesString !~ /EFST_POSTDELAY/ ) {

        # Ensure the player still exists before casting.
        my $player = $req->{target} eq $char->{name} ? $char : Match::player( $req->{target}, 1 );
        if ( !$player ) {
            warning sprintf "[buffplease] Ignoring request to use skill [%s] on user [%s] because they disappeared.\n", $req->{skill}, $req->{target};
            next;
        }

        # Make sure we have the skill.
        my $skill = Skill->new( idn => $req->{skill} );
        if ( !$skill ) {
            warning sprintf "[buffplease] Ignoring request to use skill [%s] on user [%s] because we don't have that skill.\n", $req->{skill}, $req->{target};
            next;
        }

        # Obey permissions.
        if ( $buff->{permission} eq 'guild' && !in_array( $buff->{guilds}, $player->{guild}->{name} ) ) {
            warning sprintf "[buffplease] Ignoring request to use skill [%s] on user [%s] because they are not in a whitelisted guild.\n", $req->{skill}, $req->{target};
            next;
        }

        # Assume the cast failed after five seconds.
        $timeout->{timeout} = 5;

        # Remember this skill as the last skill we cast.
        $last_skill = $req->{skill};

        message "[buffplease] Using skill [$skill] on user [$player].\n";
        my $skillTask = Task::UseSkill->new(
            actor     => $char,
            target    => $player,
            actorList => $playersList,
            skill     => $skill,
        );
        $taskManager->add( Task::ErrorReport->new( task => $skillTask ) );

        # TODO: Target this code specifically at Blessing, because skills with EFST_POSTDELAY don't have this problem.
        # Force the task to immediately try to cast the skill.
        # This speeds up cast time by about 0.5 seconds when casting Blessing then Heal on iRO.
        # $skillTask->castSkill;

        last;
    }
}

sub skillUsed {
    my ( undef, $args ) = @_;

    # Kyrie doesn't tell me I finished casting.
    return if $args->{sourceID} ne $accountID and $args->{skillID} != 73;
    return if $args->{skillID} != $last_skill;

    $timeout->{timeout} = 0;

    my $time = time;

    my $actor = Actor::get( $args->{targetID} );

    # Skill 28 is heal
    if ( $args->{skillID} == 28 ) {
        $users->{ $actor->{name} }->{lastHeal} = $time;
        $users->{ $actor->{name} }->{healFor} -= $args->{amount};

        # If the player requested to be healed for a specific amount (heal 10k please) and they still need more heals...
        if ( $users->{ $actor->{name} }->{healFor} > 0 ) {

            # Extend their please.
            $users->{ $actor->{name} }->{pleased_at} = $time;

            # Add heal to the queue again
            unshift @$commands, { skill => 28, user => $actor->{name}, target => $actor->{name}, created_at => $time };
            warning sprintf "[buffplease] Still need to heal user [%s] for [%d]. Re-queuing heal.\n", $actor->{name}, $users->{ $actor->{name} }->{healFor};
        }
    }
}

sub parseStatus {
    my ( undef, $args ) = @_;

    return if $args->{ID} ne $accountID;

    # Status type 46 is EFST_POSTDELAY
    return if $args->{type} != 46;
    return if !$args->{tick};

    # Get the skill cooldown and wait that long before trying to do anything else
    $timeout = { time => time, timeout => $args->{tick} / 1000 };
}

sub parseChat {
    my ( $hook, $args ) = @_;

    return if !$config{buffPlease};

    my $msg  = $hook eq 'packet_selfChat' ? $args->{msg}  : $args->{Msg};
    my $user = $hook eq 'packet_selfChat' ? $args->{user} : $args->{MsgUser};

    # The target of this request, which may not be the message sender.
    my $target = $user;

    my $nreq = @$requests;

    # Loop through the list of available skills
    my @requests;
    foreach my $skillID ( keys %Skill::DynamicInfo::skills ) {
        my $skillName = Skill->new( idn => $skillID );

        # Trim whitespace from skill names, Gravity is not to be trusted!
        $skillName =~ s/^\s+|\s+$//g;

        next if $buff->{ignore}->{$skillName};

        # Add alias matches if the alias is a valid regex.
        $skillName .= "|$buff->{aliases}->{$skillName}" if $buff->{aliases}->{$skillName} && eval { qr/$buff->{aliases}->{$skillName}/ };

        # If the skill name occurs in this user's message
        next if $msg !~ /$skillName/i;

        # Match the string following a skill name
        $msg =~ m/(?:$skillName)\w*\s*(?:"([^"]+)"|'([^']+)'|(\S+))/i;

        # Save it
        my $potentialPlayer = $1 || $2 || $3;

        # Make sure it's defined and not please
        if ( $potentialPlayer and $potentialPlayer !~ $please_regex ) {
            if ( my $player = Match::player( $potentialPlayer, 1 ) ) {
                $target = $player->{name};
            } elsif ( $char->{name} =~ /^\Q$potentialPlayer\E/i ) {
                $target = $char->{name};
            }
        }

        message sprintf "[buffplease] Adding request to use skill [%s] on user [%s].\n", $skillID, $target;
        push @$requests, { skill => $skillID, user => $user, target => $target, created_at => time };
    }

    # Please?
    $users->{$user}->{pleased_at} = time if $msg =~ $please_regex;

    # Heal 10k, 4000, etc.
    if ( $msg =~ /([0-9,]+)\s*([kx]\b)?/i ) {
        my ( $hp, $modifier ) = ( $1, $2 );

        $hp =~ s/,//g;

        $hp *= 1000 if $modifier;

        # Most people don't have more than 30,000 HP
        $hp = min( $hp, 30000 );

        $users->{$target}->{healFor} = $hp;
    }

    # HEAL ME MORE!!!
    # If this user has already been healed in the past 10 seconds
    if ( $msg =~ $more_regex && !timeOut( $users->{$target}->{lastHeal}, 10 ) ) {

        # Extend their please.
        $users->{$target}->{pleased_at} = time;

        message sprintf "[buffplease] Adding request to use skill [%s] on user [%s].\n", 28, $target;
        push @$requests, { skill => 28, user => $user, target => $target, created_at => time };

        # Someone asking for more probably wants a couple heals
        $users->{$target}->{healFor} = max( $users->{$target}->{healFor}, 5000 );
    }

    # Plz?
    # Unless this person has already been corrected.
    if ( $nreq != @$requests and $msg =~ $plz_regex and timeOut( $users->{$user}->{plzed_at}, 30 ) ) {
        $users->{$user}->{plzed_at} = time;
        my $randomPhrase = $buff->{wit}->[ rand @{ $buff->{wit} } ];
        Commands::run( "c $randomPhrase" );
    }

    if ( $msg =~ /debug/i ) {
        print( Dumper( $requests ) );
        print( Dumper( $commands ) );
        print( Dumper( $users ) );
        print( Dumper( $buff ) );
    }
}

# Case-insensitive, every letter must be repeated 1+ times, match on word boundaries.
# list_to_regex( 'plz', 'pls' ) => '\b(?i:p+l+z+|p+l+s+)\b'
sub list_to_regex {
    '\b(?i:' . join(
        '|',
        map {
            join '', map {"\Q$_\E+"} split //, $_
        } @_
    ) . ')\b';
}

1;
