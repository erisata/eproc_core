%/--------------------------------------------------------------------
%| Copyright 2013-2017 Erisata, UAB (Ltd.)
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
%%% Generic active state implementation. It is designed to be used
%%% with the eproc_fsm behaviour. Example of its usage:
%%%
%%%     handle_state({closed, cleaning_up} = State, Trigger, Data) ->
%%%         eproc_gen_active:state(State, Trigger, Data,
%%%             {do_cleanup, fun do_cleanup/1},
%%%             {step_retry, ?STEP_RETRY, retry},
%%%             #{ok => {closed, finalizing}}
%%%         );
%%%
%%% TODO: Add tests.
%%%
-module(eproc_gen_active).
-compile([{parse_transform, lager_transform}]).
-export([state/4]).

%%
%%  Public API.
%%
state(State, Trigger, Data, Params) when is_map(Params) ->
    Do = case maps:get(do, Params, undefined) of
        {DoEvent, DoFun} when is_function(DoFun, 2) ->
            {DoEvent, DoFun};
        {DoEvent, DoFun} when is_function(DoFun, 1) ->
            {DoEvent, fun (_SN, SD) -> DoFun(SD) end};
        {DoEvent, DoMod} when is_atom(DoMod) ->
            DoFun = case erlang:function_exported(DoMod, DoEvent, 2) of
                true  -> fun (SN,  SD) -> DoMod:DoEvent(SN, SD) end;
                false -> fun (_SN, SD) -> DoMod:DoEvent(SD) end
            end,
            {DoEvent, DoFun}
    end,
    Retry = case maps:get(retry, Params, undefined) of
        {RetryEvent, RetryTimeout, RetryName} -> {RetryEvent, RetryTimeout, RetryName};
        {RetryEvent, RetryTimeout}            -> {RetryEvent, RetryTimeout, RetryEvent};
        undefined                             -> undefined
    end,
    GiveupActionToFun = fun
        (Function) when is_function(Function, 1) ->
            Function;
        ({suspend, Reason}) ->
            fun(SD) ->
                lager:warning("Giving up on ~p. Suspending instance.", [State]),
                ok = eproc_fsm:suspend(Reason),
                {next_state, State, SD}
            end;
        (NextState) ->
            fun(SD) ->
                lager:warning("Giving up on ~p. Going to ~p.", [State, NextState]),
                {next_state, NextState, SD}
            end
    end,
    Giveup = case maps:get(giveup, Params, undefined) of
        {GiveupEvent, GiveupTimeout, GiveupName, GiveupAction} -> {GiveupEvent, GiveupTimeout, GiveupName,  GiveupActionToFun(GiveupAction)};
        {GiveupEvent, GiveupTimeout, GiveupAction}             -> {GiveupEvent, GiveupTimeout, GiveupEvent, GiveupActionToFun(GiveupAction)};
        undefined                                              -> undefined
    end,
    Next = case maps:get(next, Params) of
        NextArg when is_function(NextArg, 1) ->
            NextArg;
        NextArg when is_map(NextArg) ->
            fun ({Tag, NewData}) ->
                {next_state, maps:get(Tag, NextArg), NewData}
            end;
        NextArg ->
            fun ({ok, NewData}) ->
                {next_state, NextArg, NewData}
            end
    end,
    Error = case maps:get(error, Params, undefined) of
        undefined ->
            fun (Reason) ->
                lager:error("Failed to ~p, reason=~p", [DoEvent, Reason]),
                {same_state, Data}  % Just wait for a retry.
            end;
        ErrorFun when is_function(ErrorFun, 1) ->
            ErrorFun
    end,
    state(State, Trigger, Data, Do, Retry, Giveup, Next, Error).

state(State, {entry, Prev}, Data, {DoEvent, _DoFun}, Retry, Giveup, _Next, _Error) ->
    ok = eproc_fsm:self_send_event(DoEvent),
    case Retry of
        {RetryEvent, RetryTimeout, RetryName} ->
            ok = eproc_timer:set(RetryName, RetryTimeout, RetryEvent, State);
        undefined ->
            ok
    end,
    case {Giveup, Prev} of
        {_,                                State} -> ok;
        {{GEvent, GTimeout, GName, _GFun}, _    } -> ok = eproc_timer:set(GName, GTimeout, GEvent, State);
        {undefined,                        _    } -> ok
    end,
    {ok, Data};

state(State, {timer, RetryEvent}, Data, _Do, {RetryEvent, _RetryTimeout, _RetryName}, _Giveup, _Next, _Error) ->
    {next_state, State, Data};

state(_State, {timer, GiveupEvent}, Data, _Do, _Retry, {GiveupEvent, _GiveupTimeout, _GiveupName, GiveupFun}, _Next, _Error) ->
    GiveupFun(Data);

state(State, {self, DoEvent}, Data, {DoEvent, DoAction}, _Retry, _Giveup, Next, Error) ->
    case DoAction(State, Data) of
        {error, Reason} -> Error(Reason);
        Other           -> Next(Other)
    end;

state(_State, {entered, _Prev}, Data, _Do, _Retry, _Giveup, _Next, _Error) ->
    {same_state, Data};

state(State, {sync, _From, Request}, Data, _Do, _Retry, _Giveup, _Next, _Error) ->
    lager:warning("Dropping unknown trigger ~p @~p", [{sync, Request}, State]),
    {reply_same, {error, undefined}, Data};

state(State, Trigger, Data, _Do, _Retry, _Giveup, _Next, _Error) ->
    lager:warning("Dropping unknown trigger ~p @~p", [Trigger, State]),
    {same_state, Data}.


