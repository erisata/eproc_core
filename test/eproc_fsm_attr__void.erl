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

%%
%%  This module can be used in callback modules for the `eproc_fsm`
%%  to manage timers associated with the FSM.
%%
-module(eproc_fsm_attr__void).
-behaviour(eproc_fsm_attr).
-export([init/2, handle_describe/2, handle_created/4, handle_updated/5, handle_removed/3, handle_event/4]).
-include("eproc.hrl").



%% =============================================================================
%%  Public API.
%% =============================================================================



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(_InstId, ActiveAttrs) ->
    Started = [ {A, undefined} || A <- ActiveAttrs ],
    {ok, Started}.


%%
%%  Describe this attribute.
%%
handle_describe(Attribute, all) ->
    handle_describe(Attribute, [some, other]);

handle_describe(Attribute, Props) when is_list(Props) ->
    {ok, [{P, handle_describe(Attribute, {prop, P})} || P <- Props]};

handle_describe(_Attribute, {prop, some}) ->
    <<"this">>;

handle_describe(_Attribute, {prop, other}) ->
    <<"another">>.


%%
%%  Attribute created.
%%
handle_created(_InstId, _Attribute, _Action, _Scope) ->
    {error, undefined}.


%%
%%  Attribute updated by user.
%%
handle_updated(_InstId, _Attribute, _AttrState, _Action, _Scope) ->
    {error, undefined}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
handle_removed(_InstId, _Attribute, _AttrState) ->
    {ok, false}.


%%
%%  Attribute event received.
%%
handle_event(_InstId, _Attribute, _AttrState, _Event) ->
    {error, not_implemented}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

