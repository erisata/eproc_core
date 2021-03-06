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

-module(eproc_event_src_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%%  Check if all the functions work.
%%
source_test() ->
    erlang:erase('eproc_event_src$source'),
    ?assertEqual(undefined, eproc_event_src:source()),
    ?assertEqual(ok, eproc_event_src:set_source(some)),
    ?assertEqual(some, eproc_event_src:source()),
    ?assertEqual(ok, eproc_event_src:remove()),
    ?assertEqual(undefined, eproc_event_src:source()).


