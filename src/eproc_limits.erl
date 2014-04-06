%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%
%%  TODO: Rewrite.
%%  This module is used to control process restarts. This module is
%%  based on ETS and can delay the calling process using constant or
%%  exponentially increasing delays.
%%
%%
%%  Examples:
%%
%%      eproc_limits:notify({eproc_fsm, InstId}, restart, [
%%          {series, delays, 1,    {10, min}, {delay, {100, ms}, 1.1, {1, hour}}},
%%          {series, giveup, 1000, {10, min}, notify}
%%      ]).
%%
%%      eproc_limits:notify({eproc_fsm, InstId}, transition, [
%%          {series, burst, 100,   {200, min}, notify},
%%          {series, total, 10000, {1, year},  notify}
%%      ]).
%%
%%
-module(eproc_limits).
-behaviour(gen_server).
-export([start_link/0, setup/3, notify/3, notify/2, reset/2, reset/1, cleanup/2, cleanup/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").


%%
%%
%%
-type exp_delay() :: {delay, MinDelay :: duration(), Coefficient :: number(), MaxDelay :: duration()}.

%%
%%
%%
-type const_delay() :: {delay, Delay :: duration()}.

%%
%%
%%
-type limit_action() :: notify | exp_delay() | const_delay().

%%
%%
%%
-type series_spec() ::
        {series,
            LimitName :: term(),
            MaxCount :: integer(),
            NewAfter :: duration(),
            Action :: limit_action()
        }.

%%
%%
%%
-type rate_spec() ::
        {rate,
            LimitName :: term(),
            MaxCount :: integer(),
            Duration :: duration(),
            Action :: limit_action()
        }.

%%
%%
%%
-type limit_spec() :: series_spec() | rate_spec().



%% =============================================================================
%%  Internal state of the module.
%% =============================================================================

%%
%%  State for the governing process.
%%
-record(state, {
}).


%%
%%  Describes single limit for a particular counter.
%%
-record(limit, {
    name    :: term(),      %% Name of the limit.
    count   :: integer(),   %% Number of notifications in this series (if its a series).
    delay   :: integer()    %% Last delay in ms, if action is a delay.
}).


%%
%%  Describes single counter.
%%  Single process can have several counters and each counter can have several limits.
%%
-record(counter, {
    key     :: {term(), term()},    %% Name of the process limit, includes process name.
    proc    :: term(),              %% Process name.
    specs   :: [limit_spec()],      %% Limit specifications.
    limits  :: [#limit{}],          %% Runtime state of the limits.
    tstamps :: [{_, _, _}]          %% List of recent notification timestamps.
}).



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Initializes the restart manager.
%%
start_link() ->
    gen_server:start_link(?MODULE, {}, []).


%%
%%  Creates or updates a counter. Counter is left unchanged is
%%  this function is called subsequently with the same parameters.
%%
-spec setup(
        Proc :: term(),
        Name :: term(),
        Spec :: undefined | limit_spec() | [limit_spec()]
    ) ->
        ok.

setup(Proc, Name, Spec) ->
    Specs = case Spec of
        undefined         -> [];
        L when is_list(L) -> L;
        S                 -> [S]
    end,
    Counter = case ets:lookup(?MODULE, {Proc, Name}) of
        [C = #counter{specs = Specs}] -> C;
        [_] -> init_counter(Proc, Name, Specs);
        [] -> init_counter(Proc, Name, Specs)
    end,
    true = ets:insert(?MODULE, Counter),
    ok.


%%
%%  TODO: Rewrite.
%%
%%  This function should be used during initialization of the process,
%%  whos restarts should be delayed. It is recomended to use asynchronous
%%  initialization in such case and call this function from the asynchronous
%%  part.
%%
%%  Several options are supported by this function:
%%
%%  `{delay, (none | {const, DelayMS} | {exp, InitDelayMs, ExpCoef})}`
%%  :   Defines restart delay strategy. Default is `none`.
%%  `{fail, {MaxRestarts, MaxTimeMS}} | {fail, never}`
%%  :   Similar to supervisor's MaxR and MaxT.
%%
%%
-spec notify(
        Proc    :: term(),
        Name    :: term(),
        Count   :: integer()
    ) ->
        ok | {reached, [LimitName :: term()]}.

notify(Proc, Name, Count) ->
    [Counter] = ets:lookup(?MODULE, {Proc, Name}),
    {ReachedLimits, NewCounter} = handle_notif(Counter, Count),
    true = ets:insert(?MODULE, NewCounter),
    case ReachedLimits of
        [] -> ok;
        _ -> {reached, ReachedLimits}
    end.


%%
%%  Convenience function, equivalent to `notify(Proc, Name, 1)`.
%%
-spec notify(
        Proc    :: term(),
        Name    :: term()
    ) ->
        ok | {reached, [LimitName :: term()]}.

notify(Proc, Name) ->
    notify(Proc, Name, 1).


%%
%%  Resets state of a particular counter.
%%
-spec reset(Proc :: term(), Name :: term()) -> ok.

reset(Proc, Name) ->
    [#counter{specs = Specs}] = ets:lookup(?MODULE, {Proc, Name}),
    NewCounter = init_counter(Proc, Name, Specs),
    true = ets:insert(?MODULE, NewCounter),
    ok.


%%
%%  Resets all counters of the specified process.
%%  This function is slower than `reset/2`.
%%
-spec reset(Proc :: term()) -> ok.

reset(Proc) ->
    Counters = ets:match_object(?MODULE, #counter{proc = Proc, _ = '_'}),
    ResetFun = fun (#counter{key = {P, N}, specs = S}) ->
        C = init_counter(P, N, S),
        true = ets:insert(?MODULE, C)
    end,
    ok = lists:foreach(ResetFun, Counters).


%%
%%  Cleanup single process counter.
%%
-spec cleanup(Proc :: term(), Name :: term()) -> ok.

cleanup(Proc, Name) ->
    true = ets:delete(?MODULE, {Proc, Name}),
    ok.


%%
%%  Cleanup all counters of the specified process.
%%  This function is slower than `cleanup/2`.
%%
-spec cleanup(Proc :: term()) -> ok.

cleanup(Proc) ->
    true = ets:match_delete(?MODULE, #counter{proc = Proc, _ = '_'}),
    ok.



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({}) ->
    ets:new(?MODULE, [
        set, public, named_table, {keypos, #counter.key},
        {write_concurrency, true}, {read_concurrency, true}
    ]),
    {ok, #state{}}.


%%
%%  Synchronous messages.
%%
handle_call(_Event, _From, State) ->
    {reply, not_implemented, State}.


%%
%%  Asynchronous messages.
%%
handle_cast(_Event, State) ->
    {noreply, State}.


%%
%%  Unknown messages.
%%
handle_info(_Event, State) ->
    {noreply, State}.


%%
%%  Invoked when process terminates.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Invoked in the case of code upgrade.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Initializes a counter.
%%
init_counter(Proc, Name, Specs) ->
    Now = os:timestamp(),
    #counter{
        key = {Proc, Name},
        proc = Proc,
        specs = Specs,
        limits = lists:map(fun init_limits/1, Specs),
        tstamps = [{Now, 0}]
    }.

init_limits({series, LimitName, _MaxCount, _NewAfter, _Action}) ->
    #limit{name = LimitName, count = 0, delay = 0};

init_limits({rate, LimitName, _MaxCount, _Duration, _Action}) ->
    #limit{name = LimitName, count = 0, delay = 0}.


%%
%%  Handles new counter notification.
%%
handle_notif(Counter = #counter{specs = Specs, limits = Limits, tstamps = TStamps}, Count) ->
    Now = os:timestamp(),
    ThisTStamp = {Now, Count},
    NewTStamps = [ThisTStamp | TStamps],
    {NewLimits, MaxDelay, MaxInterval, ReachedLimits} = handle_limit(Specs, Limits, NewTStamps, Now, Count),
    FilteredTStamps = case MaxInterval =< 1000 of
        true ->
            [];
        false ->
            {N1, N2, _} = Now,
            OldestSecs = N1 * 1000000 + N2 - (MaxInterval div 1000) - 1,
            OldestTS = {OldestSecs div 1000000, OldestSecs rem 1000000, 0},
            Filter = fun ({T, _C}) -> T >= OldestTS end,
            lists:takewhile(Filter, TStamps)
    end,
    NewCounter = Counter#counter{limits = NewLimits, tstamps = [ThisTStamp | FilteredTStamps]},
    case {ReachedLimits, MaxDelay} of
        {[], D} when D > 0 ->
            timer:sleep(MaxDelay),
            {ReachedLimits, NewCounter};
        {_, _} ->
            {ReachedLimits, NewCounter}
    end.


%%
%%  Handle particular limit of a counter.
%%
handle_limit([], [], _TStamps, _Now, _Count) ->
    {[], 0, 0, []};

handle_limit(
        [{series, LimitName, MaxCount, NewAfter, Action} | OtherSpecs],
        [Limit | OtherLimits], TStamps, NotifTime, NotifCount
    ) ->
    {NewLimits, MaxDelay, MaxInterval, ReachedLimits} = handle_limit(
        OtherSpecs, OtherLimits, TStamps, NotifTime, NotifCount
    ),
    [{LastTime, _LastCount} | _] = TStamps,
    #limit{name = LimitName, count = CurrentCount, delay = LastDelay} = Limit,
    NewAfterMS = eproc_timer:duration_to_ms(NewAfter),
    NewCount = case timer:now_diff(NotifTime, LastTime) > (NewAfterMS * 1000) of
        true  -> NotifCount;
        false -> NotifCount + CurrentCount
    end,
    {NewReachedLimits, NewDelay} = case NewCount > MaxCount of
        true  -> handle_action(LimitName, Action, ReachedLimits, LastDelay);
        false -> {ReachedLimits, 0}
    end,
    NewLimit = Limit#limit{count = NewCount, delay = NewDelay},
    NewMaxDelay = erlang:max(MaxDelay, NewDelay),
    {[NewLimit | NewLimits], NewMaxDelay, MaxInterval, NewReachedLimits};

handle_limit(
        [{rate, LimitName, MaxCount, Duration, Action} | OtherSpecs],
        [Limit | OtherLimits], TStamps, NotifTime, NotifCount
    ) ->
    {NewLimits, MaxDelay, MaxInterval, ReachedLimits} = handle_limit(
        OtherSpecs, OtherLimits, TStamps, NotifTime, NotifCount
    ),
    #limit{name = LimitName, delay = LastDelay} = Limit,
    DurationMS = eproc_timer:duration_to_ms(Duration),
    OldestTStamp = timestamp_add_ms(NotifTime, -DurationMS),
    {NewReachedLimits, NewDelay} = case rate_above(TStamps, OldestTStamp, MaxCount, 0) of
        true  -> handle_action(LimitName, Action, ReachedLimits, LastDelay);
        false -> {ReachedLimits, 0}
    end,
    NewLimit = Limit#limit{count = 0, delay = NewDelay},
    NewMaxDelay = erlang:max(MaxDelay, NewDelay),
    NewMaxInterval = erlang:max(MaxInterval, DurationMS),
    {[NewLimit | NewLimits], NewMaxDelay, NewMaxInterval, NewReachedLimits}.


%%
%%  Handles all types of actions.
%%
handle_action(LimitName, notify, ReachedLimits, _LastDelayMS) ->
    {[LimitName | ReachedLimits], 0};

handle_action(_LimitName, {delay, Delay}, ReachedLimits, _LastDelayMS) ->
    DelayMS = eproc_timer:duration_to_ms(Delay),
    {ReachedLimits, DelayMS};

handle_action(_LimitName, {delay, MinDelay, Coefficient, MaxDelay}, ReachedLimits, LastDelayMS) ->
    DelayMS = case LastDelayMS =:= 0 of
        true ->
            eproc_timer:duration_to_ms(MinDelay);
        false ->
            NewDelayMS = erlang:round(LastDelayMS * Coefficient),
            case NewDelayMS =:= LastDelayMS of
                true  -> NewDelayMS + 1;
                false -> NewDelayMS
            end
    end,
    MaxDelayMS = eproc_timer:duration_to_ms(MaxDelay),
    {ReachedLimits, erlang:min(DelayMS, MaxDelayMS)}.


%%
%%  Counts notifications.
%%
rate_above(_TSs, _OldestTS, MaxCount, Count) when MaxCount < Count ->
    true;

rate_above([], _OldestTS, _MaxCount, _Count) ->
    false;

rate_above([{TS, _C} | _OtherTS], OldestTS, _MaxCount, _Count) when TS < OldestTS ->
    false;

rate_above([{_TS, C} | OtherTS], OldestTS, MaxCount, Count) ->
    rate_above(OtherTS, OldestTS, MaxCount, Count + C).


%%
%%  Adds milliseconds to timestamp.
%%
timestamp_add_ms({T1, T2, T3}, AddMS) ->
    MS = (T1 * 1000000 + T2) * 1000000 + T3 + (AddMS * 1000),
    {MS div 1000000000000, (MS div 1000000) rem 1000000, MS rem 1000000}.



%% =============================================================================
%%  Unit tests for private functions.
%% =============================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

rate_above_test_() ->
    TStamps = [{{0, 1, 400}, 10}, {{0, 1, 300}, 10}, {{0, 1, 200}, 10}],
    [
    ?_assertEqual(true,  rate_above(TStamps, {0, 1, 150}, 25, 0)),
    ?_assertEqual(false, rate_above(TStamps, {0, 1, 150}, 35, 0)),
    ?_assertEqual(true,  rate_above(TStamps, {0, 1, 250}, 15, 0)),
    ?_assertEqual(false, rate_above(TStamps, {0, 1, 250}, 25, 0))
    ].

timestamp_add_ms_test() ->
    ?assertEqual({123, 124, 234123}, timestamp_add_ms({123, 123, 123}, 1234)).

-endif.


