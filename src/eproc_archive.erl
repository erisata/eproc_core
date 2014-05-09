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
%%  Behaviour for EProc Store archive.
%%  This behaviour is not required, altrough recommended to be used
%%  by store implementations and archive implementations. This will
%%  allow to combine them as needed.
%%
%%  TODO: Define and implement.
%%
-module(eproc_archive).
-compile([{parse_transform, lager_transform}]).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback archive_instance() -> ok.


%%
%%
%%
-callback archive_transitions() -> ok.


