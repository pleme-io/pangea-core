# frozen_string_literal: true

# Copyright 2025 The Pangea Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Contracts define typed interfaces that backends must return and templates
# can rely on. Provider-specific subclasses extend these base contracts
# with additional fields via inheritance.

require_relative 'contracts/errors'
require_relative 'contracts/security_group_accessor'
require_relative 'contracts/network_result'
require_relative 'contracts/iam_result'
require_relative 'contracts/cluster_result'
require_relative 'contracts/architecture_result'
