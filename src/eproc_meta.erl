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
%%  This module is responsible for maintaining FSM metadata. For now,
%%  the metadata is maintained as tags, that can be attached to
%%  an FSM instance.
%%
%%  Tags can be used to find FSM instances or caregorize them.
%%  Tags don't need to be unique, but required to be binaries.
%%  They are maintained as FSM attributes.
%%
-module(eproc_meta).
-behaviour(eproc_fsm_attr).
-export([add_tag/2]).
-export([init/1, handle_created/3, handle_updated/4, handle_removed/2, handle_event/3]).
-include("eproc.hrl").


-record(data, {
    tag     :: binary(),
    type    :: binary()
}).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
add_tag(Tag, Type) ->
    Name = Action = {tag, Tag, Type},
    eproc_fsm_attr:action(?MODULE, Name, Action, []).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(ActiveAttrs) ->
    {ok, [ {A, undefined} || A <- ActiveAttrs ]}.


%%
%%  Attribute created.
%%
handle_created(_Attribute, {tag, Tag, Type}, _Scope) ->
    AttrData = #data{tag = Tag, type = Type},
    AttrState = undefined,
    {create, AttrData, AttrState, true}.


%%
%%  A tag can only be updated to the same value.
%%
handle_updated(Attribute, _AttrState, {tag, Tag, Type}, _Scope) ->
    #attribute{data = AttrData} = Attribute,
    AttrData = #data{tag = Tag, type = Type},
    handled.


%%
%%  Attributes should never be removed.
%%
handle_removed(_Attribute, _AttrState) ->
    {error, tags_non_removable}.


%%
%%  Events are not used for tags.
%%
handle_event(_Attribute, _AttrState, Event) ->
    throw({unknown_event, Event}).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

