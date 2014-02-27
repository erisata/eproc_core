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
%%  Encodes / decodes erlang terms to/from XML using xmerl.
%%
-module(eproc_codec_xml).
-behaviour(eproc_codec).
-export([encode/2, decode/1]).


%% =============================================================================
%%  Callbacks for `eproc_codec`.
%% =============================================================================

%%
%%  Encode term to XML.
%%
encode(_CodecArgs, Term) ->
    Xml = xmerl:export_simple([encode(Term)], xmerl_xml),
    {ok, Xml}.


%%
%%  Decode XML to Erlang term.
%%
decode(_Xml) ->
    % TODO: Implement.
    {error, not_implemented}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

encode(Term) when is_tuple(Term) ->
    L = tuple_to_list(Term),
    {tuple, [encode(E) || E <- L]};
    
encode(Term = [H | _]) when is_integer(H), H < 256 ->
    {string, [Term]};

encode(Term) when is_list(Term) ->
    {list, [encode(E) || E <- Term]};
    
encode(Term) when is_atom(Term) ->
    A = atom_to_list(Term),
    {atom, [A]};

encode(Term) when is_integer(Term) ->
    I = integer_to_list(Term),
    {integer, [I]};
    
encode(Term) when is_binary(Term) ->
    B = binary_to_list(Term),
    {binary, [B]}.