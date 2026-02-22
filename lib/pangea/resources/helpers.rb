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


module Pangea
  module Resources
    # Helper functions available in template context
    module Helpers
      # Create a terraform reference to another resource
      # @param resource_type [Symbol] The resource type (e.g., :aws_vpc)
      # @param resource_name [Symbol] The resource name
      # @param attribute [Symbol] The attribute to reference (e.g., :id)
      # @return [String] Terraform reference string
      def ref(resource_type, resource_name, attribute)
        "${#{resource_type}.#{resource_name}.#{attribute}}"
      end
      
      # Create a data source reference
      # @param data_type [Symbol] The data source type
      # @param data_name [Symbol] The data source name  
      # @param attribute [Symbol] The attribute to reference
      # @return [String] Terraform data reference string
      def data_ref(data_type, data_name, attribute)
        "${data.#{data_type}.#{data_name}.#{attribute}}"
      end
      
      # Create a variable reference
      # @param var_name [Symbol] The variable name
      # @return [String] Terraform variable reference string
      def var(var_name)
        "${var.#{var_name}}"
      end
      
      # Create a local value reference
      # @param local_name [Symbol] The local value name
      # @return [String] Terraform local reference string
      def local(local_name)
        "${local.#{local_name}}"
      end
    end
  end
end