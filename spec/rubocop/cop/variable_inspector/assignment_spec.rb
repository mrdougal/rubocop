# encoding: utf-8

require 'spec_helper'

module Rubocop
  module Cop
    module VariableInspector
      describe Assignment do
        include ASTHelper
        include AST::Sexp

        let(:ast) do
          processed_source = Rubocop::SourceParser.parse(source)
          processed_source.ast
        end

        let(:source) do
          <<-END
            class SomeClass
              def some_method(flag)
                puts 'Hello World!'

                if flag > 0
                  foo = 1
                end
              end
            end
          END
        end

        let(:def_node) do
          found_node = scan_node(ast, include_origin_node: true) do |node|
            break node if node.type == :def
          end
          fail 'No def node found!' unless found_node
          found_node
        end

        let(:lvasgn_node) do
          found_node = scan_node(ast) do |node|
            break node if node.type == :lvasgn
          end
          fail 'No lvasgn node found!' unless found_node
          found_node
        end

        let(:name) { lvasgn_node.children.first }
        let(:scope) { Scope.new(def_node) }
        let(:variable) { Variable.new(name, lvasgn_node, scope) }
        let(:assignment) { Assignment.new(lvasgn_node, variable) }

        describe '.new' do
          let(:variable) { double('variable') }

          context 'when an assignment node is passed' do
            it 'does not raise error' do
              node = s(:lvasgn, :foo)
              expect { Assignment.new(node, variable) }.not_to raise_error
            end
          end

          context 'when an argument declaration node is passed' do
            it 'raises error' do
              node = s(:arg, :foo)
              expect { Assignment.new(node, variable) }
                .to raise_error(ArgumentError)
            end
          end

          context 'when any other type node is passed' do
            it 'raises error' do
              node = s(:def)
              expect { Assignment.new(node, variable) }
                .to raise_error(ArgumentError)
            end
          end
        end

        describe '#name' do
          it 'returns the variable name' do
            expect(assignment.name).to eq(:foo)
          end
        end

        describe '#ancestor_nodes_in_scope' do
          it 'returns its ancestor nodes in the scope excluding scope node' do
            ancestor_types = assignment.ancestor_nodes_in_scope.map(&:type)
            expect(ancestor_types).to eq([:begin, :if])
          end
        end

        describe '#branch_point_node' do
          context 'when it is not in branch' do
            let(:source) do
              <<-END
                def some_method(flag)
                  foo = 1
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_point_node).to be_nil
            end
          end

          context 'when it is inside of if' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if flag
                    foo = 1
                  end
                end
              END
            end

            it 'returns the if node' do
              expect(assignment.branch_point_node.type).to eq(:if)
            end
          end

          context 'when it is inside of else of if' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if flag
                  else
                    foo = 1
                  end
                end
              END
            end

            it 'returns the if node' do
              expect(assignment.branch_point_node.type).to eq(:if)
            end
          end

          context 'when it is inside of if condition' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if foo = 1
                    do_something
                  end
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_point_node).to be_nil
            end
          end

          context 'when multiple if are nested' do
            context 'and it is inside of inner if' do
              let(:source) do
                <<-END
                  def some_method(a, b)
                    if a
                      if b
                        foo = 1
                      end
                    end
                  end
                END
              end

              it 'returns inner if node' do
                if_node = assignment.branch_point_node
                expect(if_node.type).to eq(:if)
                condition_node = if_node.children.first
                expect(condition_node).to eq(s(:lvar, :b))
              end
            end

            context 'and it is inside of inner if condition' do
              let(:source) do
                <<-END
                  def some_method(a, b)
                    if a
                      if foo = 1
                        do_something
                      end
                    end
                  end
                END
              end

              it 'returns the next outer if node' do
                if_node = assignment.branch_point_node
                expect(if_node.type).to eq(:if)
                condition_node = if_node.children.first
                expect(condition_node).to eq(s(:lvar, :a))
              end
            end
          end

          context 'when it is inside of when of case' do
            let(:source) do
              <<-END
                def some_method(flag)
                  case flag
                  when 1
                    foo = 1
                  end
                end
              END
            end

            it 'returns the case node' do
              expect(assignment.branch_point_node.type).to eq(:case)
            end
          end

          context 'when it is on the left side of &&' do
            let(:source) do
              <<-END
                def some_method
                  (foo = 1) && do_something
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_point_node).to be_nil
            end
          end

          context 'when it is on the right side of &&' do
            let(:source) do
              <<-END
                def some_method
                  do_something && (foo = 1)
                end
              END
            end

            it 'returns the and node' do
              expect(assignment.branch_point_node.type).to eq(:and)
            end
          end

          context 'when it is on the left side of ||' do
            let(:source) do
              <<-END
                def some_method
                  (foo = 1) || do_something
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_point_node).to be_nil
            end
          end

          context 'when it is on the right side of ||' do
            let(:source) do
              <<-END
                def some_method
                  do_something || (foo = 1)
                end
              END
            end

            it 'returns the or node' do
              expect(assignment.branch_point_node.type).to eq(:or)
            end
          end

          context 'when multiple && are chained' do
            context 'and it is on the right side of the right &&' do
              let(:source) do
                <<-END
                  def some_method
                    do_something && do_anything && (foo = 1)
                  end
                END
              end

              it 'returns the right and node' do
                and_node = assignment.branch_point_node
                expect(and_node.type).to eq(:and)
                right_side_node = and_node.children[1]
                expect(right_side_node.type).to eq(:begin)
              end
            end

            context 'and it is on the right side of the left &&' do
              let(:source) do
                <<-END
                  def some_method
                    do_something && (foo = 1) && do_anything
                  end
                END
              end

              it 'returns the left and node' do
                and_node = assignment.branch_point_node
                expect(and_node.type).to eq(:and)
                right_side_node = and_node.children[1]
                expect(right_side_node.type).to eq(:begin)
              end
            end
          end

          context 'when it is inside of begin with rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  rescue
                    do_something
                  end
                end
              END
            end

            it 'returns the rescue node' do
              expect(assignment.branch_point_node.type).to eq(:rescue)
            end
          end

          context 'when it is inside of rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    do_something
                  rescue
                    foo = 1
                  end
                end
              END
            end

            it 'returns the rescue node' do
              expect(assignment.branch_point_node.type).to eq(:rescue)
            end
          end

          context 'when it is inside of begin with ensure' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  ensure
                    do_something
                  end
                end
              END
            end

            it 'returns the ensure node' do
              expect(assignment.branch_point_node.type).to eq(:ensure)
            end
          end

          context 'when it is inside of ensure' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    do_something
                  ensure
                    foo = 1
                  end
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_point_node).to be_nil
            end
          end

          context 'when it is inside of begin without rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  end
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_point_node).to be_nil
            end
          end
        end

        describe '#branch_body_node' do
          context 'when it is not in branch' do
            let(:source) do
              <<-END
                def some_method(flag)
                  foo = 1
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_body_node).to be_nil
            end
          end

          context 'when it is inside body of if' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if flag
                    foo = 1
                    puts foo
                  end
                end
              END
            end

            it 'returns the body node' do
              expect(assignment.branch_body_node.type).to eq(:begin)
            end
          end

          context 'when it is inside body of else of if' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if flag
                    do_something
                  else
                    foo = 1
                    puts foo
                  end
                end
              END
            end

            it 'returns the body node' do
              expect(assignment.branch_body_node.type).to eq(:begin)
            end
          end

          context 'when it is on the right side of &&' do
            let(:source) do
              <<-END
                def some_method
                  do_something && (foo = 1)
                end
              END
            end

            it 'returns the right side node' do
              expect(assignment.branch_body_node.type).to eq(:begin)
            end
          end

          context 'when it is on the right side of ||' do
            let(:source) do
              <<-END
                def some_method
                  do_something || (foo = 1)
                end
              END
            end

            it 'returns the right side node' do
              expect(assignment.branch_body_node.type).to eq(:begin)
            end
          end

          context 'when it is inside of begin with rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  rescue
                    do_something
                  end
                end
              END
            end

            it 'returns the body node' do
              expect(assignment.branch_body_node.type).to eq(:lvasgn)
            end
          end

          context 'when it is inside of rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    do_something
                  rescue
                    foo = 1
                  end
                end
              END
            end

            it 'returns the resbody node' do
              expect(assignment.branch_body_node.type).to eq(:resbody)
            end
          end

          context 'when it is inside of begin with ensure' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  ensure
                    do_something
                  end
                end
              END
            end

            it 'returns the body node' do
              expect(assignment.branch_body_node.type).to eq(:lvasgn)
            end
          end
        end

        describe '#branch_id' do
          context 'when it is not in branch' do
            let(:source) do
              <<-END
                def some_method(flag)
                  foo = 1
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_id).to be_nil
            end
          end

          context 'when it is inside body of if' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if flag
                    foo = 1
                    puts foo
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_if_true' do
              expect(assignment.branch_id).to match(/^\d+_if_true/)
            end
          end

          context 'when it is inside body of else of if' do
            let(:source) do
              <<-END
                def some_method(flag)
                  if flag
                    do_something
                  else
                    foo = 1
                    puts foo
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_if_false' do
              expect(assignment.branch_id).to match(/^\d+_if_false/)
            end
          end

          context 'when it is inside body of when of case' do
            let(:source) do
              <<-END
                def some_method(flag)
                  case flag
                  when first
                    do_something
                  when second
                    foo = 1
                    puts foo
                  else
                    do_something
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_case_whenINDEX' do
              expect(assignment.branch_id).to match(/^\d+_case_when1/)
            end
          end

          context 'when it is inside body of when of case' do
            let(:source) do
              <<-END
                def some_method(flag)
                  case flag
                  when first
                    do_something
                  when second
                    do_something
                  else
                    foo = 1
                    puts foo
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_case_else' do
              expect(assignment.branch_id).to match(/^\d+_case_else/)
            end
          end

          context 'when it is on the left side of &&' do
            let(:source) do
              <<-END
                def some_method
                  (foo = 1) && do_something
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_id).to be_nil
            end
          end

          context 'when it is on the right side of &&' do
            let(:source) do
              <<-END
                def some_method
                  do_something && (foo = 1)
                end
              END
            end

            it 'returns BRANCHNODEID_and_right' do
              expect(assignment.branch_id).to match(/^\d+_and_right/)
            end
          end

          context 'when it is on the left side of ||' do
            let(:source) do
              <<-END
                def some_method
                  (foo = 1) || do_something
                end
              END
            end

            it 'returns nil' do
              expect(assignment.branch_id).to be_nil
            end
          end

          context 'when it is on the right side of ||' do
            let(:source) do
              <<-END
                def some_method
                  do_something || (foo = 1)
                end
              END
            end

            it 'returns BRANCHNODEID_or_right' do
              expect(assignment.branch_id).to match(/^\d+_or_right/)
            end
          end

          context 'when it is inside of begin with rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  rescue
                    do_something
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_rescue_main' do
              expect(assignment.branch_id).to match(/^\d+_rescue_main/)
            end
          end

          context 'when it is inside of rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    do_something
                  rescue FirstError
                    do_something
                  rescue SecondError
                    foo = 1
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_rescue_rescueINDEX' do
              expect(assignment.branch_id).to match(/^\d+_rescue_rescue1/)
            end
          end

          context 'when it is inside of else of rescue' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    do_something
                  rescue FirstError
                    do_something
                  rescue SecondError
                    do_something
                  else
                    foo = 1
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_rescue_else' do
              expect(assignment.branch_id).to match(/^\d+_rescue_else/)
            end
          end

          context 'when it is inside of begin with ensure' do
            let(:source) do
              <<-END
                def some_method(flag)
                  begin
                    foo = 1
                  ensure
                    do_something
                  end
                end
              END
            end

            it 'returns BRANCHNODEID_ensure_main' do
              expect(assignment.branch_id).to match(/^\d+_ensure_main/)
            end
          end
        end

        describe '#meta_assignment_node' do
          context 'when it is += operator assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo += 1
                end
              END
            end

            it 'returns op_asgn node' do
              expect(assignment.meta_assignment_node.type).to eq(:op_asgn)
            end
          end

          context 'when it is ||= operator assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo ||= 1
                end
              END
            end

            it 'returns or_asgn node' do
              expect(assignment.meta_assignment_node.type).to eq(:or_asgn)
            end
          end

          context 'when it is &&= operator assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo &&= 1
                end
              END
            end

            it 'returns and_asgn node' do
              expect(assignment.meta_assignment_node.type).to eq(:and_asgn)
            end
          end

          context 'when it is multiple assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo, bar = [1, 2]
                end
              END
            end

            it 'returns masgn node' do
              expect(assignment.meta_assignment_node.type).to eq(:masgn)
            end
          end
        end

        describe '#operator' do
          context 'when it is normal assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo = 1
                end
              END
            end

            it 'returns =' do
              expect(assignment.operator).to eq('=')
            end
          end

          context 'when it is += operator assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo += 1
                end
              END
            end

            it 'returns +=' do
              expect(assignment.operator).to eq('+=')
            end
          end

          context 'when it is ||= operator assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo ||= 1
                end
              END
            end

            it 'returns ||=' do
              expect(assignment.operator).to eq('||=')
            end
          end

          context 'when it is &&= operator assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo &&= 1
                end
              END
            end

            it 'returns &&=' do
              expect(assignment.operator).to eq('&&=')
            end
          end

          context 'when it is multiple assignment' do
            let(:source) do
              <<-END
                def some_method
                  foo, bar = [1, 2]
                end
              END
            end

            it 'returns =' do
              expect(assignment.operator).to eq('=')
            end
          end
        end
      end
    end
  end
end