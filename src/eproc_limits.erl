%/--------------------------------------------------------------------
%| Copyright 2013-2016 Erisata, UAB (Ltd.)
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

%%%
%%% This module allows to manage some reccuring events. Several
%%% strategies are supported for this. The process that reports the events
%%% can be delayed with constant or exponentially increasing delays
%%% or can be notified, when some counter limit is reached.
%%%
%%% This module is used in `eproc_fsm` to limit restart rate as well
%%% as transition and message rates. Nevertheless, this module is not
%%% tied to the `eproc_fsm` and can be used by other modules.
%%%
%%% This module manages counters, and each of the counters can have
%%% multiple limits set. Each limit has own action, that is applied
%%% when the limit is reached. If several actions are fired,
%%% the following rules apply:
%%%
%%%   * If several limits with delay actions are triggered,
%%%     maximum of all the delays is returned.
%%%   * If delay is triggered together with notification,
%%%     the delays are ignored and the notifications are returned.
%%%
%%% Each process can have several counters, that can be later notified,
%%% reset or cleaned up in one go. Altrough process name is an
%%% arbitraty term and is not related to Erlang process in any way.
%%%
%%% Delays, returned by this module (as a response to `notify/*`)
%%% are extracted from the time intervals between the notifications
%%% when calculating limits. This is done in order to avoid interferrence
%%% of delays and event rates/intervals. Without this, the delays would make
%%% limit conditions to fail, when the limit time intervals are smaller
%%% than delays (this is the common case).
%%%
%%% The notifications that trigger reach of some of the limits are dropped
%%% and leave all the counters unchanged. This is needed to avoid the deadlocks
%%% that may occur at a notification rate constantly exceeding the configured
%%% limits. If the rejected events were counted, the limit would be reached
%%% all the time, and all the notifications would be reported as a limit reach.
%%%
%%% Several types of counter limits are implemented:
%%%
%%%   * `series` - counts events in a series, where events in one
%%%     series have distance not more than specified time interval.
%%%   * `rate` - measures event rate. This is similar to supervisor's
%%%     restart counters.
%%%
%%% For more details, look at descriptions of the corresponding types.
%%%
%%% Examples:
%%%
%%%     eproc_limits:setup({eproc_fsm, InstId}, restart, [
%%%         {series, delays, 1,    {10, min}, {delay, {100, ms}, 1.1, {1, hour}}},
%%%         {series, giveup, 1000, {10, min}, notify}
%%%     ]).
%%%
%%%     eproc_limits:setup({eproc_fsm, InstId}, transition, [
%%%         {series, burst, 100,   {200, min}, notify},
%%%         {series, total, 10000, {1, year},  notify}
%%%     ]).
%%%
-module(eproc_limits).
-behaviour(gen_server).
-export([start_link/0, setup/3, notify/3, notify/2, reset/2, reset/1, cleanup/2, cleanup/1, info/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").


%%
%%  Constant delay action. If this event is fired, it aways delays
%%  the calling process for the specific time.
%%
-type const_delay() :: {delay, Delay :: duration()}.


%%
%%  Exponential delay action. When triggered for the first time
%%  in the failure series, it delays the process calling `notify/2-3`
%%  for MinDelay. Each subsequent trigger causes delay increased by
%%  Coefficient comparing to the previous delay. The delays will not
%%  exceed the MaxDelay.
%%
%%  If the corresponding counter is dropped bellow the limit, all
%%  the delays are reset and the next delay will be MinDelay again.
%%
-type exp_delay() :: {delay, MinDelay :: duration(), Coefficient :: number(), MaxDelay :: duration()}.


%%
%%  Action, that is triggered when particular limit is reached.
%%  Delay actions are discussed above. The `notify` action causes
%%  the `notify/2-3` function to return names of the reached limits
%%  in form of `{reached, [LimitName]}`.
%%
-type limit_action() :: notify | exp_delay() | const_delay().


%%
%%  Limit specification, counting events in a series, where intervals
%%  between the events in the series are less that NewAfter.
%%  The Action is triggered is series contains more than MaxCount events.
%%
%%  If an interval between two subsequent events is more that NewAfter,
%%  old series data is discarded and new series is started to count.
%%
%%  This limit is efficient in both: cpu and memory usage and has
%%  constant complexity to number of events.
%%
-type series_spec() ::
        {series,
            LimitName :: term(),
            MaxCount :: integer(),
            NewAfter :: duration(),
            Action :: limit_action()
        }.

%%
%%  Limit specification counting events per time interval.
%%  It acts similarly to the supervisor's restart counters.
%%  This limit triggers the Action if more than MaxCount events
%%  has been occured during the specified Duration.
%%
%%  This limit implementation is less effective comparing to the
%%  `series` limit. It has linear complexity with regards to
%%  event count arrived during the Duration. The same applies
%%  for memory and CPU. One should avoid this limit for very
%%  large durations (hours and more).
%%
-type rate_spec() ::
        {rate,
            LimitName :: term(),
            MaxCount :: integer(),
            Duration :: duration(),
            Action :: limit_action()
        }.

%%
%%  Limit specification can be series limit or rate limit.
%%  Each of them are described above in more details.
%%
-type limit_spec() :: series_spec() | rate_spec().



%%% ============================================================================
%%% Internal state of the module.
%%% ============================================================================

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
%%  Describes single notification for the counter.
%%
-record(notif, {
    time    :: integer(),       %% Notification time in ms.
    count   :: integer(),       %% Count of events (usually 1).
    delay   :: integer()        %% Delay, calculated based on the notification.
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
    notifs  :: [#notif{}]           %% List of recent notifications.
}).



%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Initializes the restart manager.
%%
start_link() ->
    gen_server:start_link(?MODULE, {}, []).


%%
%%  Creates or updates a counter. Counter is left unchanged is
%%  this function is called subsequently with the same parameters.
%%
%%  Counter specification is updated if it was absent or was
%%  different from the new specification. In this case all the
%%  counter state is reset.
%%
-spec setup(
        ProcessName :: term(),
        CounterName :: term(),
        Spec :: undefined | limit_spec() | [limit_spec()]
    ) ->
        ok.

setup(ProcessName, CounterName, Spec) ->
    Specs = case Spec of
        undefined         -> [];
        L when is_list(L) -> L;
        S                 -> [S]
    end,
    Counter = case ets:lookup(?MODULE, {ProcessName, CounterName}) of
        [C = #counter{specs = Specs}] -> C;
        [_] -> init_counter(ProcessName, CounterName, Specs);
        [] -> init_counter(ProcessName, CounterName, Specs)
    end,
    true = ets:insert(?MODULE, Counter),
    ok.


%%
%%  Notifies the counter that event has occured.
%%  The function can be used to notify several (Count) events in one call.
%%  Timestamp for all such events will be considered the same.
%%
-spec notify(
        ProcessName :: term(),
        CounterName :: term(),
        Count       :: integer()
    ) ->
        ok |
        {reached, [LimitName :: term()]} |
        {delay, DelayMS :: integer()} |
        {error, {not_found, CounterName :: term()}}.

notify(_ProcessName, _CounterName, 0) ->
    ok;

notify(ProcessName, CounterName, Count) when Count > 0 ->
    case ets:lookup(?MODULE, {ProcessName, CounterName}) of
        [] ->
            {error, {not_found, CounterName}};
        [Counter] ->
            ThisNotif = #notif{time = timestamp_ms(), count = Count, delay = 0},
            {Response, NewLimits, FilteredNotifs, Delay} = case handle_notif(Counter, ThisNotif) of
                {ok, L, N, [], 0} -> {ok,           L, N, 0};
                {ok, L, N, [], D} -> {{delay, D},   L, N, D};
                {ok, L, N, R, _D} -> {{reached, R}, L, N, 0}
            end,
            case Response of
                {reached, Limits} ->
                    % Do not count the events, that were rejected.
                    {reached, Limits};
                _ ->
                    NewNotifs  = [ThisNotif#notif{delay = Delay} | FilteredNotifs],
                    NewCounter = Counter#counter{limits = NewLimits, notifs = NewNotifs},
                    true = ets:insert(?MODULE, NewCounter),
                    Response
            end
    end.


%%
%%  Updates several counters at once. Returns all reached limits or
%%  maximal delay or ok, if all counters respond with ok.
%%
-spec notify(
        ProcessName :: term(),
        Counters    :: [{CounterName :: term(), Count :: integer()}]
    ) ->
        ok |
        {reached, [{CounterName :: term(), [LimitName :: term()]}]} |
        {delay, DelayMS :: integer()} |
        {error, {not_found, CounterName :: term()}}.

notify(ProcessName, Counters) ->
    NowMS = timestamp_ms(),
    AggregateResponse = fun
        ({_, {error, E}},   _Other           ) -> {error, E};
        ({N, {reached, R}}, {reached, OtherR}) -> {reached, [{N, R} | OtherR]};
        ({_, _Other},       {reached, OtherR}) -> {reached, OtherR};
        ({N, {reached, R}}, _Other           ) -> {reached, [{N, R}]};
        ({_, {delay, D}},   {delay, OtherD}  ) -> {delay, erlang:max(D, OtherD)};
        ({_, {delay, D}},   ok               ) -> {delay, D};
        ({_, ok},           Other            ) -> Other
    end,
    HandleCounters = fun ({CounterName, Count}, {HandledCounters, CommonResponse}) ->
        case ets:lookup(?MODULE, {ProcessName, CounterName}) of
            [] ->
                {
                    HandledCounters,
                    {error, {not_found, CounterName}}
                };
            [Counter] ->
                ThisNotif = #notif{time = NowMS, count = Count, delay = 0},
                {Response, NewLimits, FilteredNotifs} = case handle_notif(Counter, ThisNotif) of
                    {ok, L, N, [], 0} -> {ok,           L, N};
                    {ok, L, N, [], D} -> {{delay, D},   L, N};
                    {ok, L, N, R, _D} -> {{reached, R}, L, N}
                end,
                {
                    [{Counter, NewLimits, ThisNotif, FilteredNotifs} | HandledCounters],
                    AggregateResponse({CounterName, Response}, CommonResponse)
                }
        end
    end,
    {HandledCounters, CommonResponse} = lists:foldr(HandleCounters, {[], ok}, Counters),
    SaveCounters = fun ({Counter, NewLimits, ThisNotif, FilteredNotifs}, Delay) ->
        NewNotifs  = [ThisNotif#notif{delay = Delay} | FilteredNotifs],
        NewCounter = Counter#counter{limits = NewLimits, notifs = NewNotifs},
        true = ets:insert(?MODULE, NewCounter),
        Delay
    end,
    case CommonResponse of
        ok ->
            lists:foldl(SaveCounters, 0, HandledCounters),
            ok;
        {delay, Delay} ->
            lists:foldl(SaveCounters, Delay, HandledCounters),
            {delay, Delay};
        {reached, Limits} ->
            % Do not count the events, that were rejected.
            {reached, Limits};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Resets state of a particular counter.
%%
-spec reset(ProcessName :: term(), CounterName :: term()) -> ok.

reset(ProcessName, CounterName) ->
    [#counter{specs = Specs}] = ets:lookup(?MODULE, {ProcessName, CounterName}),
    NewCounter = init_counter(ProcessName, CounterName, Specs),
    true = ets:insert(?MODULE, NewCounter),
    ok.


%%
%%  Resets all counters of the specified process.
%%  This function is slower than `reset/2`.
%%
-spec reset(ProcessName :: term()) -> ok.

reset(ProcessName) ->
    Counters = ets:match_object(?MODULE, #counter{proc = ProcessName, _ = '_'}),
    ResetFun = fun (#counter{key = {P, N}, specs = S}) ->
        C = init_counter(P, N, S),
        true = ets:insert(?MODULE, C)
    end,
    ok = lists:foreach(ResetFun, Counters).


%%
%%  Cleanup single process counter.
%%
-spec cleanup(ProcessName :: term(), CounterName :: term()) -> ok.

cleanup(ProcessName, CounterName) ->
    true = ets:delete(?MODULE, {ProcessName, CounterName}),
    ok.


%%
%%  Cleanup all counters of the specified process.
%%  This function is slower than `cleanup/2`.
%%
-spec cleanup(ProcessName :: term()) -> ok.

cleanup(ProcessName) ->
    true = ets:match_delete(?MODULE, #counter{proc = ProcessName, _ = '_'}),
    ok.


%%
%%  Get some info on the limits subsystem.
%%
info(count) ->
    ets:info(?MODULE, size).



%%% ============================================================================
%%% Callbacks for `gen_server`.
%%% ============================================================================

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



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


%%
%%  Initializes a counter.
%%
init_counter(ProcessName, CounterName, Specs) ->
    NowMS = timestamp_ms(),
    #counter{
        key = {ProcessName, CounterName},
        proc = ProcessName,
        specs = Specs,
        limits = lists:map(fun init_limits/1, Specs),
        notifs = [#notif{time = NowMS, count = 0, delay = 0}]
    }.

init_limits({series, LimitName, _MaxCount, _NewAfter, _Action}) ->
    #limit{name = LimitName, count = 0, delay = 0};

init_limits({rate, LimitName, _MaxCount, _Duration, _Action}) ->
    #limit{name = LimitName, count = 0, delay = 0}.


%%
%%  Handles new counter notification.
%%
handle_notif(#counter{specs = Specs, limits = Limits, notifs = Notifs}, ThisNotif) ->
    {NewLimits, MaxDelay, OldestUsed, ReachedLimits} = handle_limit(Specs, Limits, Notifs, ThisNotif),
    FilteredNotifs = cleanup_notifs(Notifs, OldestUsed),
    {ok, NewLimits, FilteredNotifs, ReachedLimits, MaxDelay}.


%%
%%  Handle particular limit of a counter.
%%
handle_limit([], [], _Notifs, _ThisNotif) ->
    {[], 0, 0, []};

handle_limit(
        [{series, LimitName, MaxCount, NewAfter, Action} | OtherSpecs],
        [Limit | OtherLimits], Notifs, ThisNotif
    ) ->
    {NewLimits, MaxDelay, OldestUsed, ReachedLimits} = handle_limit(
        OtherSpecs, OtherLimits, Notifs, ThisNotif
    ),
    #notif{time = ThisNotifTime, count = ThisNotifCount} = ThisNotif,
    [#notif{time = LastNotifTime, delay = LastNotifDelay} | _] = Notifs,
    #limit{name = LimitName, count = CurrentCount, delay = LastDelay} = Limit,
    NewAfterMS = eproc_timer:duration_to_ms(NewAfter),
    NewCount = case (ThisNotifTime - LastNotifTime - LastNotifDelay) > NewAfterMS of
        true  -> ThisNotifCount;
        false -> ThisNotifCount + CurrentCount
    end,
    {NewReachedLimits, NewDelay} = case NewCount > MaxCount of
        true  -> handle_action(LimitName, Action, ReachedLimits, LastDelay);
        false -> {ReachedLimits, 0}
    end,
    NewLimit = Limit#limit{count = NewCount, delay = NewDelay},
    NewMaxDelay = erlang:max(MaxDelay, NewDelay),
    {[NewLimit | NewLimits], NewMaxDelay, OldestUsed, NewReachedLimits};

handle_limit(
        [{rate, LimitName, MaxCount, Duration, Action} | OtherSpecs],
        [Limit | OtherLimits], Notifs, ThisNotif
    ) ->
    {NewLimits, MaxDelay, OldestUsed, ReachedLimits} = handle_limit(
        OtherSpecs, OtherLimits, Notifs, ThisNotif
    ),
    #notif{time = ThisNotifTime} = ThisNotif,
    #limit{name = LimitName, delay = LastDelay} = Limit,
    DurationMS = eproc_timer:duration_to_ms(Duration),
    OldestMS = ThisNotifTime - DurationMS,
    {NewReachedLimits, NewDelay} = case rate_above([ThisNotif | Notifs], OldestMS, MaxCount, 0) of
        {true,  ActualOldestMS} -> handle_action(LimitName, Action, ReachedLimits, LastDelay);
        {false, ActualOldestMS} -> {ReachedLimits, 0}
    end,
    NewLimit = Limit#limit{count = 0, delay = NewDelay},
    NewMaxDelay = erlang:max(MaxDelay, NewDelay),
    NewOldestUsed = erlang:min(OldestUsed, ActualOldestMS),
    {[NewLimit | NewLimits], NewMaxDelay, NewOldestUsed, NewReachedLimits}.


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
%%  Drop old timestamps.
%%
cleanup_notifs(Notifs, OldestUsed) ->
    Filter = fun (#notif{time = T}) -> T >= OldestUsed end,
    lists:takewhile(Filter, Notifs).


%%
%%  Counts notifications over provided time interval.
%%
rate_above(_Notifs, OldestMS, MaxCount, Count) when MaxCount < Count ->
    {true, OldestMS};

rate_above([], OldestMS, _MaxCount, _Count) ->
    {false, OldestMS};

rate_above([#notif{time = T, delay = D} | _OtherNotifs], OldestMS, _MaxCount, _Count) when T < (OldestMS - D) ->
    {false, OldestMS - D};

rate_above([#notif{count = C, delay = D} | OtherNotifs], OldestMS, MaxCount, Count) ->
    rate_above(OtherNotifs, OldestMS - D, MaxCount, Count + C).


%%
%%  Convert timestamp to milliseconds.
%%
timestamp_ms({T1, T2, T3}) ->
    (T1 * 1000000 + T2) * 1000 + (T3 div 1000).


%%
%%  Convert current timestamp to milliseconds.
%%
timestamp_ms() ->
    timestamp_ms(os:timestamp()).



%%% ============================================================================
%%% Unit tests for private functions.
%%% ============================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

rate_above_test_() ->
    Notifs = [
        #notif{time = 400, count = 10, delay = 0},
        #notif{time = 300, count = 10, delay = 0},
        #notif{time = 200, count = 10, delay = 0},
        #notif{time =   0, count = 10, delay = 100}
    ],
    [
        ?_assertMatch({true,  _}, rate_above(Notifs,  50, 35, 0)),
        ?_assertMatch({false, _}, rate_above(Notifs,  50, 45, 0)),
        ?_assertMatch({true,  _}, rate_above(Notifs, 150, 25, 0)),
        ?_assertMatch({false, _}, rate_above(Notifs, 150, 35, 0)),
        ?_assertMatch({true,  _}, rate_above(Notifs, 250, 15, 0)),
        ?_assertMatch({false, _}, rate_above(Notifs, 250, 25, 0))
    ].

-endif.


