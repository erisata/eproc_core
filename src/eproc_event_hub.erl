%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
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
%%% Event hub for receiving messages from processes, that don't know
%%% receiver's PID. This is common in the case, when one want to
%%% receive an asynchronous events from a persistent FSMs and don't want
%%% to store transient data (PID) in the persistent store (as an event or
%%% process state).
%%%
%%% This module allows to perform receive in two steps by creating listening
%%% session first (similar to process inbox) and the performing receive
%%% on it.
%%%
%%% ETS match specifications are used for selecting events.
%%%
%%% For distributed environments, this only works for nodes, connected
%%% using Erlang distribution (uses `gen_server:abcast/2`).
%%%
-module(eproc_event_hub).
-bahaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1, start/1, listen/2, recv/3, notify/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").
-export_type([session_ref/0]).

-opaque session_ref() :: {session, SessionId :: reference(), Start :: os:timestamp(), Duration :: integer()}.


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start this hub.
%%
-spec start_link(
        Name :: otp_name()
    ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(Name) ->
    gen_server:start_link(Name, ?MODULE, {}, []).


%%
%%  Start this hub without linking.
%%
-spec start(
        Name :: otp_name()
    ) ->
        {ok, pid()} | ignore | {error, term()}.

start(Name) ->
    gen_server:start(Name, ?MODULE, {}, []).


%%
%%  Start a listening session.
%%
-spec listen(
        Name     :: otp_ref(),
        Duration :: integer()
    ) ->
        {ok, SessionRef :: session_ref()}.

listen(Name, Duration) ->
    Start = os:timestamp(),
    Caller = self(),
    SessionId = erlang:make_ref(),
    Session = {session, SessionId, Start, Duration},
    ok = gen_server:call(Name, {listen, SessionId, Caller, Duration}),
    {ok, Session}.


%%
%%  Wait for the specific event.
%%
-spec recv(
        Name        :: otp_ref(),
        SessionRef  :: session_ref(),
        MatchSpec   :: ets:match_spec()
    ) ->
        {ok, Event :: term()} |
        {error, Reason :: term()}.

recv(Name, {session, SessionId, Start, Duration}, MatchSpec) ->
    Now = os:timestamp(),
    Timeout = Duration - (timer:now_diff(Now, Start) div 1000),
    case Timeout >= 0 of
        true  -> gen_server:call(Name, {recv, SessionId, MatchSpec}, Timeout + 500);
        false -> {error, timeout}
    end.


%%
%%  Event senders invoke this to publish events.
%%
-spec notify(
        Name    :: otp_ref(),
        Event   :: term()
    ) ->
        ok.

notify(Name, Event) ->
    abcast = gen_server:abcast(Name, {notify, Event}),
    ok.



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(session, {
    sid         :: reference(),
    monitor     :: reference(),
    cleanup     :: reference(),
    mode        :: {listen, Events :: [term()]} |
                   {recv, From :: term(), MatchSpecCompiled :: ets:comp_match_spec()}
}).

-record(state, {
    sessions    :: [#session{}]
}).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  Initialize.
%%
init({}) ->
    State = #state{
        sessions = []
    },
    {ok, State}.


%%
%%  Synchronous messages.
%%
handle_call({listen, SessionId, Caller, Duration}, _From, State = #state{sessions = Sessions}) ->
    Monitor = erlang:monitor(process, Caller),
    Cleanup = erlang:send_after(Duration, self(), {cleanup, SessionId}),
    Session = #session{
        sid = SessionId,
        monitor = Monitor,
        cleanup = Cleanup,
        mode = {listen, []}
    },
    NewSessions = [Session | Sessions],
    {reply, ok, State#state{sessions = NewSessions}};

handle_call({recv, SessionId, MatchSpec}, From, State = #state{sessions = Sessions}) ->
    case lists:keytake(SessionId, #session.sid, Sessions) of
        false ->
            {reply, {error, no_session}, State};
        {value, #session{mode = {recv, _From, _MatchSpecCompiled}}, _OtherSessions} ->
            {reply, {error, duplicate_revc}, State};
        {value, Session = #session{mode = {listen, Events}, monitor = Monitor, cleanup = Cleanup}, OtherSessions} ->
            MatchSpecCompiled = ets:match_spec_compile(MatchSpec),
            case ets:match_spec_run(Events, MatchSpecCompiled) of
                [Event | _] ->
                    _ = erlang:cancel_timer(Cleanup),
                    true = erlang:demonitor(Monitor),
                    {reply, {ok, Event}, State#state{sessions = OtherSessions}};
                [] ->
                    NewSession = Session#session{mode = {recv, From, MatchSpecCompiled}},
                    NewSessions = [NewSession | OtherSessions],
                    {noreply, State#state{sessions = NewSessions}}
            end
    end.


%%
%%  Asynchronous messages.
%%
handle_cast({notify, Event}, State = #state{sessions = Sessions}) ->
    FoldFun = fun
        (Session = #session{mode = {listen, Events}}, OtherSessions) ->
            NewListen = {listen, [Event | Events]},
            [Session#session{mode = NewListen} | OtherSessions];
        (Session = #session{mode = {recv, From, MatchSpecCompiled}, monitor = Monitor, cleanup = Cleanup}, OtherSessions) ->
            case ets:match_spec_run([Event], MatchSpecCompiled) of
                [] ->
                    [Session | OtherSessions];
                [Matched] ->
                    _ = gen_server:reply(From, {ok, Matched}),
                    _ = erlang:cancel_timer(Cleanup),
                    true = erlang:demonitor(Monitor),
                    OtherSessions
            end
    end,
    NewSessions = lists:foldl(FoldFun, [], Sessions),
    {noreply, State#state{sessions = NewSessions}}.


%%
%%  Other messages.
%%
handle_info({'DOWN', MonitorRef, process, _Caller, _Info}, State = #state{sessions = Sessions}) ->
    case lists:keytake(MonitorRef, #session.monitor, Sessions) of
        false ->
            {noreply, State};
        {value, #session{}, OtherSessions} ->
            {noreply, State#state{sessions = OtherSessions}}
    end;

handle_info({cleanup, SessionId}, State = #state{sessions = Sessions}) ->
    case lists:keytake(SessionId, #session.sid, Sessions) of
        false ->
            {noreply, State};
        {value, #session{monitor = Monitor, mode = {listen, _Events}}, OtherSessions} ->
            true = erlang:demonitor(Monitor),
            {noreply, State#state{sessions = OtherSessions}};
        {value, #session{monitor = Monitor, mode = {recv, From, _MatchSpecCompiled}}, OtherSessions} ->
            _ = gen_server:reply(From, {error, timeout}),
            true = erlang:demonitor(Monitor),
            {noreply, State#state{sessions = OtherSessions}}
    end.


%%
%%  Unused.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Unused.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================
