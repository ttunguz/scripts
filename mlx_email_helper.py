#!/usr/bin/env python3
"""
MLX Email Helper Script
Handles JSON escaping and API calls for NeoVim integration
"""

import json
import sys
import requests
import argparse
from typing import Optional

def escape_for_json(text: str) -> str:
    """Properly escape text for JSON"""
    return json.dumps(text)[1:-1]  # Remove the outer quotes

def call_mlx_api(prompt: str, max_tokens: int = 150, server_url: str = "http://localhost:8080") -> Optional[str]:
    """Call the MLX API with proper JSON handling"""
    
    # Truncate very long prompts to prevent memory issues
    if len(prompt) > 8000:
        prompt = prompt[-8000:]  # Keep the most recent part
        print(f"[INFO] Truncated prompt to {len(prompt)} characters", file=sys.stderr)
    
    payload = {
        "model": "mlx-community/gemma-3-12b-it-4bit",
        "prompt": prompt,
        "max_tokens": max_tokens
    }
    
    try:
        response = requests.post(
            f"{server_url}/v1/completions",
            headers={"Content-Type": "application/json"},
            json=payload,  # Use json parameter for automatic escaping
            timeout=60
        )
        
        if response.status_code == 200:
            result = response.json()
            if "choices" in result and len(result["choices"]) > 0:
                return result["choices"][0]["text"].strip()
            else:
                print(f"[ERROR] Unexpected response format: {result}", file=sys.stderr)
                return None
        else:
            print(f"[ERROR] HTTP {response.status_code}: {response.text}", file=sys.stderr)
            return None
            
    except requests.exceptions.Timeout:
        print("[ERROR] Request timed out", file=sys.stderr)
        return None
    except requests.exceptions.ConnectionError:
        print("[ERROR] Could not connect to MLX server. Is it running on port 8080?", file=sys.stderr)
        return None
    except Exception as e:
        print(f"[ERROR] {str(e)}", file=sys.stderr)
        return None

def summarize_email(email_content: str, max_tokens: int = 150) -> Optional[str]:
    """Summarize email content"""
    prompt = f"Summarize this email in 2-3 sentences:\n\n{email_content}"
    return call_mlx_api(prompt, max_tokens)

def generate_reply(email_content: str, max_tokens: int = 200) -> Optional[str]:
    """Generate a reply to email content"""
    prompt = f"Write a brief, professional reply to this email:\n\n{email_content}\n\nReply:"
    return call_mlx_api(prompt, max_tokens)

def main():
    parser = argparse.ArgumentParser(description='MLX Email Helper for NeoVim')
    parser.add_argument('--action', choices=['summarize', 'reply', 'custom'], 
                       default='summarize', help='Action to perform')
    parser.add_argument('--prompt', help='Custom prompt for custom action')
    parser.add_argument('--max-tokens', type=int, default=150, help='Max tokens to generate')
    parser.add_argument('--server-url', default='http://localhost:8080', help='MLX server URL')
    parser.add_argument('--input-file', help='Read input from file instead of stdin')
    
    args = parser.parse_args()
    
    # Read input
    if args.input_file:
        try:
            with open(args.input_file, 'r') as f:
                content = f.read()
        except Exception as e:
            print(f"[ERROR] Could not read file {args.input_file}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        content = sys.stdin.read()
    
    if not content.strip():
        print("[ERROR] No input provided", file=sys.stderr)
        sys.exit(1)
    
    # Process based on action
    result = None
    
    if args.action == 'summarize':
        result = summarize_email(content, args.max_tokens)
    elif args.action == 'reply':
        result = generate_reply(content, args.max_tokens)
    elif args.action == 'custom':
        if not args.prompt:
            print("[ERROR] --prompt required for custom action", file=sys.stderr)
            sys.exit(1)
        full_prompt = f"{args.prompt}\n\n{content}"
        result = call_mlx_api(full_prompt, args.max_tokens, args.server_url)
    
    if result:
        print(result)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()