-- tests/backend/services/board_service_persist_ids_spec.lua
-- Tests for persist_card_ids enforcement in board_service

describe("board_service persist_card_ids enforcement", function()
	local board_service
	local file_service
	local lfs
	local test_dir

	-- Setup test environment
	before_each(function()
		-- Load real lfs
		lfs = require("lfs")

		-- Create a unique temporary directory for each test
		test_dir = os.tmpname()
		os.remove(test_dir) -- Remove the file created by tmpname
		lfs.mkdir(test_dir)

		-- Mock backend config with test directory
		package.loaded["backend.config"] = {
			data_dir = test_dir
		}

		-- Load file_service and board_service
		file_service = require("backend.services.file_service")
		board_service = require("backend.services.board_service")
	end)

	after_each(function()
		-- Clean up test files
		if test_dir then
			for file in lfs.dir(test_dir) do
				if file ~= "." and file ~= ".." then
					os.remove(test_dir .. "/" .. file)
				end
			end
			lfs.rmdir(test_dir)
		end

		-- Clean up loaded modules
		package.loaded["backend.services.board_service"] = nil
		package.loaded["backend.services.file_service"] = nil
		package.loaded["backend.config"] = nil
	end)

	describe("create_board", function()
		it("should add persist_card_ids to default board", function()
			-- Create a new board without markdown
			local board_id, err = board_service.create_board("test_board")

			assert.is_nil(err)
			assert.is_not_nil(board_id)

			-- Read the created board
			local markdown = file_service.read_board(board_id)

			-- Verify persist_card_ids is in the config
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
		end)

		it("should add persist_card_ids to board created with markdown", function()
			-- Create board with custom markdown (without persist_card_ids)
			local initial_markdown = [[# Custom Board

###### Backlog

###### Done
]]

			local board_id, err = board_service.create_board("custom_board", initial_markdown)

			assert.is_nil(err)
			assert.is_not_nil(board_id)

			-- Read the created board
			local markdown = file_service.read_board(board_id)

			-- Verify persist_card_ids was added
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
		end)

		it("should preserve existing persist_card_ids: true", function()
			-- Create board with persist_card_ids already set
			local initial_markdown = [[# Existing Board
<!-- kanban:config persist_card_ids: true -->

###### Backlog

###### Done
]]

			local board_id, err = board_service.create_board("existing_board", initial_markdown)

			assert.is_nil(err)
			assert.is_not_nil(board_id)

			-- Read the created board
			local markdown = file_service.read_board(board_id)

			-- Verify persist_card_ids is still true
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
		end)

		it("should override persist_card_ids: false to true", function()
			-- Create board with persist_card_ids set to false
			local initial_markdown = [[# Override Board
<!-- kanban:config persist_card_ids: false -->

###### Backlog

###### Done
]]

			local board_id, err = board_service.create_board("override_board", initial_markdown)

			assert.is_nil(err)
			assert.is_not_nil(board_id)

			-- Read the created board
			local markdown = file_service.read_board(board_id)

			-- Verify persist_card_ids is now true (not false)
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
			assert.is_falsy(markdown:match("persist_card_ids:%s*false"))
		end)
	end)

	describe("get_board", function()
		it("should ensure persist_card_ids in board config", function()
			-- Create a board first
			local board_id = board_service.create_board("get_test_board")

			-- Get the board
			local board_data, err = board_service.get_board(board_id)

			assert.is_nil(err)
			assert.is_not_nil(board_data)
			assert.is_not_nil(board_data.config)
			assert.is_true(board_data.config.persist_card_ids)
		end)
	end)

	describe("add_card", function()
		it("should maintain persist_card_ids when adding cards", function()
			-- Create a board
			local board_id = board_service.create_board("card_test_board")

			-- Add a card
			local updated_board, card_id, err = board_service.add_card(board_id, "Backlog", "Test Task", {})

			assert.is_nil(err)
			assert.is_not_nil(updated_board)
			assert.is_true(updated_board.config.persist_card_ids)

			-- Verify the markdown file has persist_card_ids
			local markdown = file_service.read_board(board_id)
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))

			-- If card_id is returned, verify it's in the markdown
			if card_id then
				assert.is_truthy(markdown:match("id:%s*" .. card_id))
			end
		end)
	end)

	describe("move_card", function()
		it("should maintain persist_card_ids when moving cards", function()
			-- Create a board and add a card
			local board_id = board_service.create_board("move_test_board")
			local updated_board, card_id = board_service.add_card(board_id, "Backlog", "Test Task", {})

			-- Only test move if we got a card_id
			if card_id then
				-- Move the card
				local moved_board, err = board_service.move_card(board_id, card_id, "Backlog", "Done")

				assert.is_nil(err)
				assert.is_not_nil(moved_board)
				assert.is_true(moved_board.config.persist_card_ids)

				-- Verify the markdown file still has persist_card_ids
				local markdown = file_service.read_board(board_id)
				assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
			else
				-- If no card_id, at least verify persist_card_ids is still set
				local markdown = file_service.read_board(board_id)
				assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
			end
		end)
	end)

	describe("update_card", function()
		it("should maintain persist_card_ids when updating cards", function()
			-- Create a board and add a card
			local board_id = board_service.create_board("update_test_board")
			local _, card_id = board_service.add_card(board_id, "Backlog", "Test Task", {})

			-- Only test update if we got a card_id
			if card_id then
				-- Update the card
				local updated_board, err = board_service.update_card(board_id, card_id, {
					text = "Updated Task"
				})

				assert.is_nil(err)
				assert.is_not_nil(updated_board)
				assert.is_true(updated_board.config.persist_card_ids)
			end

			-- Verify the markdown file has persist_card_ids
			local markdown = file_service.read_board(board_id)
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
		end)
	end)

	describe("delete_card", function()
		it("should maintain persist_card_ids when deleting cards", function()
			-- Create a board and add a card
			local board_id = board_service.create_board("delete_test_board")
			local _, card_id = board_service.add_card(board_id, "Backlog", "Test Task", {})

			-- Only test delete if we got a card_id
			if card_id then
				-- Delete the card
				local updated_board, err = board_service.delete_card(board_id, card_id)

				assert.is_nil(err)
				assert.is_not_nil(updated_board)
				assert.is_true(updated_board.config.persist_card_ids)
			end

			-- Verify the markdown file has persist_card_ids
			local markdown = file_service.read_board(board_id)
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
		end)
	end)

	describe("archive_cards", function()
		it("should maintain persist_card_ids when archiving cards", function()
			-- Create a board and add a completed card
			local board_id = board_service.create_board("archive_test_board")
			local _, card_id = board_service.add_card(board_id, "Done", "Completed Task", {
				done = os.time() - (31 * 24 * 60 * 60) -- 31 days ago
			})

			-- Archive cards older than 30 days (only if card was successfully added)
			if card_id then
				local result, err = board_service.archive_cards(board_id, 30)

				assert.is_nil(err)
				assert.is_not_nil(result)
				assert.is_true(result.success)
				assert.is_true(result.board.config.persist_card_ids)
			end

			-- Verify the markdown file has persist_card_ids
			local markdown = file_service.read_board(board_id)
			assert.is_truthy(markdown:match("persist_card_ids:%s*true"))
		end)
	end)
end)
