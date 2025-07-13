-- NeoVim MLX Integration
-- Add this to your NeoVim config to integrate with the MLX email helper

local M = {}

-- Path to the MLX email helper script
local MLX_HELPER_PATH = "/Users/tomasztunguz/Documents/coding/scripts/mlx_email_helper.py"

-- Function to get selected text or entire buffer
local function get_text_content()
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '' then
        -- Visual mode - get selected text
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        local lines = vim.fn.getline(start_pos[2], end_pos[2])
        
        if #lines == 1 then
            -- Single line selection
            lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
        else
            -- Multi-line selection
            lines[1] = string.sub(lines[1], start_pos[3])
            lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
        end
        
        return table.concat(lines, '\n')
    else
        -- Normal mode - get entire buffer
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        return table.concat(lines, '\n')
    end
end

-- Function to run MLX helper with error handling
local function run_mlx_helper(action, content, max_tokens)
    max_tokens = max_tokens or 150
    
    -- Create temporary file with content
    local tmp_file = os.tmpname()
    local file = io.open(tmp_file, 'w')
    if not file then
        vim.notify("Error: Could not create temporary file", vim.log.levels.ERROR)
        return nil
    end
    
    file:write(content)
    file:close()
    
    -- Run the helper script
    local cmd = string.format('python3 "%s" --action %s --max-tokens %d --input-file "%s"', 
                             MLX_HELPER_PATH, action, max_tokens, tmp_file)
    
    local handle = io.popen(cmd .. ' 2>&1')
    if not handle then
        os.remove(tmp_file)
        vim.notify("Error: Could not run MLX helper", vim.log.levels.ERROR)
        return nil
    end
    
    local result = handle:read('*a')
    local success = handle:close()
    os.remove(tmp_file)
    
    if not success then
        vim.notify("MLX Helper Error: " .. result, vim.log.levels.ERROR)
        return nil
    end
    
    return result:gsub('%s+$', '') -- Trim trailing whitespace
end

-- Summarize email content
function M.summarize_email()
    local content = get_text_content()
    if not content or content == '' then
        vim.notify("No content to summarize", vim.log.levels.WARN)
        return
    end
    
    vim.notify("Summarizing email...", vim.log.levels.INFO)
    local summary = run_mlx_helper('summarize', content, 150)
    
    if summary then
        -- Insert summary at cursor position
        local lines = vim.split(summary, '\n')
        vim.api.nvim_put(lines, 'l', true, true)
        vim.notify("Email summarized successfully", vim.log.levels.INFO)
    end
end

-- Generate email reply
function M.generate_reply()
    local content = get_text_content()
    if not content or content == '' then
        vim.notify("No content to reply to", vim.log.levels.WARN)
        return
    end
    
    vim.notify("Generating reply...", vim.log.levels.INFO)
    local reply = run_mlx_helper('reply', content, 200)
    
    if reply then
        -- Insert reply at cursor position
        local lines = vim.split(reply, '\n')
        vim.api.nvim_put(lines, 'l', true, true)
        vim.notify("Reply generated successfully", vim.log.levels.INFO)
    end
end

-- Custom prompt function
function M.custom_prompt()
    local content = get_text_content()
    if not content or content == '' then
        vim.notify("No content selected", vim.log.levels.WARN)
        return
    end
    
    -- Get custom prompt from user
    local prompt = vim.fn.input("Enter custom prompt: ")
    if not prompt or prompt == '' then
        return
    end
    
    vim.notify("Processing with custom prompt...", vim.log.levels.INFO)
    
    -- Create temporary file with content
    local tmp_file = os.tmpname()
    local file = io.open(tmp_file, 'w')
    file:write(content)
    file:close()
    
    local cmd = string.format('python3 "%s" --action custom --prompt "%s" --max-tokens 200 --input-file "%s"', 
                             MLX_HELPER_PATH, prompt:gsub('"', '\\"'), tmp_file)
    
    local handle = io.popen(cmd .. ' 2>&1')
    local result = handle:read('*a')
    local success = handle:close()
    os.remove(tmp_file)
    
    if success and result then
        local lines = vim.split(result:gsub('%s+$', ''), '\n')
        vim.api.nvim_put(lines, 'l', true, true)
        vim.notify("Custom prompt processed successfully", vim.log.levels.INFO)
    else
        vim.notify("Error: " .. (result or "Unknown error"), vim.log.levels.ERROR)
    end
end

-- Set up key mappings
function M.setup()
    -- Leader key mappings
    vim.keymap.set({'n', 'v'}, '<leader>es', M.summarize_email, { desc = 'Email: Summarize' })
    vim.keymap.set({'n', 'v'}, '<leader>er', M.generate_reply, { desc = 'Email: Generate Reply' })
    vim.keymap.set({'n', 'v'}, '<leader>ec', M.custom_prompt, { desc = 'Email: Custom Prompt' })
    
    -- Create user commands
    vim.api.nvim_create_user_command('EmailSummarize', M.summarize_email, {})
    vim.api.nvim_create_user_command('EmailReply', M.generate_reply, {})
    vim.api.nvim_create_user_command('EmailCustom', M.custom_prompt, {})
    
    vim.notify("MLX Email integration loaded", vim.log.levels.INFO)
end

return M