%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, Ltd.
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
%%  This module is used to control process restarts. This module is
%%  based on ETS and can delay the calling process using constant or
%%  exponentially increasing delays.
%%
-module(eproc_restart).
-behaviour(gen_server).
-export([start_link/0, restarted/2, cleanup/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


%%
%%  Describes single managed process.
%%
-record(entry, {
    key,        %% Process key.
    last,       %% Time of the last restart.
    count,      %% Number of restarts in this series.
    delay       %% Next delay.
}).



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Initializes the restart manager.
%%
start_link() ->
    gen_server:start_link(?MODULE, {[]}, []).


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
-spec restarted(Key :: term(), Opts :: list()) ->
        ok | fail.

restarted(Key, Opts) ->
    restarted(Key, proplists:get_value(delay, Opts, none), Opts).


%%
%%  Used to cleanup info of a managed process. This function should be used
%%  before stopping the process in a normal (managed) way.
%%
-spec cleanup(term()) -> ok.

cleanup(Key) ->
    true = ets:delete(eproc_restart, Key),
    ok.



%% =============================================================================
%%  Internal state of the module.
%% =============================================================================

-record(state, {
    opts
}).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({Opts}) ->
    ets:new(eproc_restart, [set, public, named_table, {keypos, #entry.key}]),
    {ok, #state{opts = Opts}}.


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
%%  Handles different restart delay strategies.
%%
restarted(_Key, none, _Opts) ->
    ok;

restarted(Key, {const, DelayMS}, Opts) ->
    Now = erlang:now(),
    case ets:lookup(eproc_restart, Key) of
        [] ->
            ok = write_new(Key, Now, DelayMS);
        [Entry] ->
            ok = timer:sleep(DelayMS),
            ok = write_next(Entry, Now, DelayMS),
            update_entry(Entry, Now, DelayMS, DelayMS, Opts)
    end;

restarted(Key, {exp, InitDelayMs, ExpCoef}, Opts) ->
    Now = erlang:now(),
    case ets:lookup(eproc_restart, Key) of
        [] ->
            ok = write_new(Key, Now, InitDelayMs);
        [Entry = #entry{delay = DelayMS}] ->
            ok = timer:sleep(DelayMS),
            NextDelayMS = erlang:trunc(DelayMS * ExpCoef),
            update_entry(Entry, Now, InitDelayMs, NextDelayMS, Opts)
    end.


%%
%%  Update entries and handle fail conditions.
%%
update_entry(Entry, Now, InitDelayMs, NextDelayMS, Opts) ->
    case proplists:get_value(fail, Opts, never) of
        never ->
            ok = write_next(Entry, Now, NextDelayMS);
        {MaxRestarts, MaxTimeMS} ->
            #entry{last = Last, count = Count} = Entry,
            case timer:now_diff(Now, Last) > (MaxTimeMS * 1000) of
                true ->
                    ok = write_reset(Entry, Now, InitDelayMs);
                false ->
                    ok = write_next(Entry, Now, NextDelayMS),
                    case Count > MaxRestarts of
                        true -> fail;
                        false -> ok
                    end
            end
    end.


%%
%%  Adds new entry or resets it.
%%
write_new(Key, Time, InitDelayMS) ->
    true = ets:insert(eproc_restart, #entry{key = Key, last = Time, count = 1, delay = InitDelayMS}),
    ok.


%%
%%  Updates existing entry.
%%
write_next(Entry = #entry{count = Count}, Time, NextDelayMS) ->
    true = ets:insert(eproc_restart, Entry#entry{last = Time, count = Count + 1, delay = NextDelayMS}),
    ok.


%%
%%  Reset the existing entry.
%%
write_reset(Entry, Time, InitDelayMS) ->
    true = ets:insert(eproc_restart, Entry#entry{last = Time, count = 1, delay = InitDelayMS}),
    ok.

