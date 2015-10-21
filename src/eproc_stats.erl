%/--------------------------------------------------------------------
%| Copyright 2015 Erisata, UAB (Ltd.)
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
%%% Collects and provides runtime statictics.
%%% Implemented using Exometer.
%%%
-module(eproc_stats).
-compile([{parse_transform, lager_transform}]).
-export([
    info/1,
    instance_created/1,
    instance_completed/2,
    transition_completed/1,
    message_registered/1,
    get_value/3
]).

-define(APP, eproc_core).


%%% ============================================================================
%%% API functions.
%%% ============================================================================


%%
%%
%%
info(list) ->
    Entries = exometer:find_entries([axb]),
    {ok, [ Name || {Name, _Type, enabled} <- Entries ]}.


%%
%%  Updates execution stats.
%%
instance_created(Module) ->
    ok = inc_spiral([?APP, inst, Module, count]).

instance_completed(Module, error) ->
    ok = inc_spiral([?APP, inst, Module, err]);

instance_completed(Module, DurationUS) when is_integer(DurationUS) ->
    ok = update_spiral([?APP, inst, Module, dur], DurationUS).

transition_completed(Module) ->
    ok = inc_spiral([?APP, trans, Module, count]).

message_registered(Module) ->
    ok = inc_spiral([?APP, msg, Module, count]).


%%
%%
%%
get_value(Object, Module, Type) ->
    get_value_spiral([?APP, Object, Module, Type]).


%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
inc_spiral(Name) ->
    ok = exometer:update_or_create(Name, 1, spiral, []).


%%
%%
%%
update_spiral(Name, Value) ->
    ok = exometer:update_or_create(Name, Value, spiral, []).


%%
%%
%%
get_optional(Name, DataPoint) ->
    case exometer:get_value(Name, DataPoint) of
        {ok, [{DataPoint, Val}]} -> Val;
        {error, not_found} -> 0
    end.


%%
%%
%%
get_value_spiral(MatchHead) ->
    Entries = exometer:find_entries(MatchHead),
    lists:foldr(fun({Name, _Type, _Status}, Acc) ->
        Acc + get_optional(Name, one)
    end, 0, Entries).


