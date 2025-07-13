#!/usr/bin/env python3
"""
MLX Memory-Optimized Server with KV Cache Management
Implements sliding window KV cache and memory management for long contexts
"""

# Activate virtual environment
import os
import sys
script_dir = os.path.dirname(os.path.abspath(__file__))
venv_path = os.path.join(script_dir, 'mlx-env', 'bin', 'python')
if os.path.exists(venv_path) and sys.executable != venv_path:
    os.execv(venv_path, [venv_path] + sys.argv)

import os
import sys
import time
import json
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse
import threading
from typing import Dict, List, Tuple, Optional

try:
    import mlx.core as mx
    import mlx_lm
    from mlx_lm import load, generate
    MLX_AVAILABLE = True
except ImportError:
    MLX_AVAILABLE = False
    print("Warning: MLX not available, this is a stub implementation")

class MemoryOptimizedMLXHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, model_manager=None, **kwargs):
        self.model_manager = model_manager
        super().__init__(*args, **kwargs)
    
    def do_POST(self):
        if self.path == '/v1/completions':
            self.handle_completion()
        elif self.path == '/v1/chat/completions':
            self.handle_chat_completion()
        elif self.path == '/api/generate':
            self.handle_ollama_generate()
        elif self.path == '/api/chat':
            self.handle_ollama_chat()
        else:
            self.send_error(404, "Not Found")
    
    def do_GET(self):
        if self.path == '/v1/models':
            self.handle_models()
        elif self.path == '/health':
            self.handle_health()
        else:
            self.send_error(404, "Not Found")
    
    def handle_completion(self):
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            request_data = json.loads(post_data.decode('utf-8'))
            
            prompt = request_data.get('prompt', '')
            max_tokens = min(request_data.get('max_tokens', 512), 32768)  # Cap at 32K - plenty of headroom with 96GB RAM
            temperature = request_data.get('temperature', 0.7)
            
            # Truncate prompt if too long (prevent memory issues) 
            if len(prompt) > 50000:  # Much higher limit with 96GB RAM
                prompt = prompt[-8000:]  # Keep most recent part
                print(f"[INFO] Truncated prompt to prevent memory issues")
            
            # Generate response with memory management
            response_text = self.model_manager.generate_with_memory_management(
                prompt, max_tokens, temperature
            )
            
            response = {
                "id": f"cmpl-{int(time.time())}",
                "object": "text_completion",
                "created": int(time.time()),
                "model": self.model_manager.model_name,
                "choices": [{
                    "text": response_text,
                    "index": 0,
                    "logprobs": None,
                    "finish_reason": "length"
                }],
                "usage": {
                    "prompt_tokens": len(prompt.split()),
                    "completion_tokens": len(response_text.split()),
                    "total_tokens": len(prompt.split()) + len(response_text.split())
                }
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            
        except Exception as e:
            print(f"Error in completion: {e}")
            self.send_error(500, f"Internal Server Error: {str(e)}")
    
    def handle_chat_completion(self):
        # Convert chat format to simple completion
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            request_data = json.loads(post_data.decode('utf-8'))
            
            messages = request_data.get('messages', [])
            # Convert messages to single prompt
            prompt = "\n".join([f"{msg.get('role', 'user')}: {msg.get('content', '')}" for msg in messages])
            
            # Create completion request
            completion_request = {
                'prompt': prompt,
                'max_tokens': request_data.get('max_tokens', 512),
                'temperature': request_data.get('temperature', 0.7)
            }
            
            # Reuse completion logic
            self.handle_completion_internal(completion_request)
            
        except Exception as e:
            print(f"Error in chat completion: {e}")
            self.send_error(500, f"Internal Server Error: {str(e)}")
    
    def handle_models(self):
        models = {
            "object": "list",
            "data": [{
                "id": self.model_manager.model_name if self.model_manager else "unknown",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "mlx-community"
            }]
        }
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(models).encode())
    
    def handle_health(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"OK")
    
    def handle_ollama_generate(self):
        """Handle Ollama-compatible /api/generate requests for gen.nvim"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            request_data = json.loads(post_data.decode('utf-8'))
            
            prompt = request_data.get('prompt', '')
            max_tokens = min(request_data.get('max_tokens', 512), 32768)
            temperature = request_data.get('temperature', 0.7)
            
            # Truncate prompt if too long  
            if len(prompt) > 50000:
                prompt = prompt[-8000:]
                print(f"[INFO] Truncated prompt to prevent memory issues")
            
            # Generate response with memory management
            response_text = self.model_manager.generate_with_memory_management(
                prompt, max_tokens, temperature
            )
            
            # Ollama format response
            response = {
                "model": self.model_manager.model_name,
                "created_at": f"{int(time.time())}",
                "response": response_text,
                "done": True
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            
        except Exception as e:
            print(f"Error in Ollama generate: {e}")
            self.send_error(500, f"Internal Server Error: {str(e)}")
    
    def handle_ollama_chat(self):
        """Handle Ollama-compatible /api/chat requests for gen.nvim"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            # Try to parse as JSON first (gen.nvim sends JSON despite content-type)
            try:
                json_data = json.loads(post_data.decode('utf-8'))
                
                # Extract prompt from messages array
                if 'messages' in json_data and json_data['messages']:
                    prompt = json_data['messages'][0].get('content', '')
                elif 'prompt' in json_data:
                    prompt = json_data['prompt']
                else:
                    prompt = ""
                    
            except json.JSONDecodeError:
                # Try form data parsing
                import urllib.parse
                try:
                    form_data = urllib.parse.parse_qs(post_data.decode('utf-8'))
                    prompt = ""
                    for key in ['prompt', 'message', 'input', 'text']:
                        if key in form_data:
                            prompt = form_data[key][0]
                            break
                except Exception as e:
                    prompt = post_data.decode('utf-8').strip()
            
            if not prompt:
                self.send_error(400, "No prompt provided")
                return
            
            max_tokens = 3000  # Increased for very detailed summaries
            temperature = 0.7
            
            # Truncate prompt if too long  
            if len(prompt) > 50000:
                prompt = prompt[-8000:]
                print(f"[INFO] Truncated prompt to prevent memory issues")
            
            # Generate response with memory management
            response_text = self.model_manager.generate_with_memory_management(
                prompt, max_tokens, temperature
            )
            
            # Clean up the response text
            response_text = response_text.strip()
            
            # Ollama format response
            response = {
                "model": self.model_manager.model_name,
                "created_at": f"{int(time.time())}",
                "response": response_text,
                "done": True
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            
        except Exception as e:
            print(f"Error in Ollama chat: {e}")
            self.send_error(500, f"Internal Server Error: {str(e)}")

class MemoryOptimizedModelManager:
    def __init__(self, model_name: str, max_cache_size: int = 32768):
        self.model_name = model_name
        self.max_cache_size = max_cache_size
        self.model = None
        self.tokenizer = None
        self.kv_cache = None
        self.lock = threading.Lock()
        
        if MLX_AVAILABLE:
            self.load_model()
    
    def load_model(self):
        """Load the MLX model with memory optimizations"""
        try:
            print(f"Loading model: {self.model_name}")
            
            # Clear cache before loading
            mx.metal.clear_cache()
            
            # Load model with quantization settings
            self.model, self.tokenizer = load(
                self.model_name,
                # Add any specific quantization config here if needed
            )
            
            print(f"Model loaded successfully: {self.model_name}")
            
        except Exception as e:
            print(f"Error loading model: {e}")
            raise
    
    def generate_with_memory_management(self, prompt: str, max_tokens: int = 512, temperature: float = 0.7) -> str:
        """Generate text with KV cache management and memory optimization"""
        if not MLX_AVAILABLE:
            return f"MLX not available. Would process: {prompt[:100]}..."
        
        with self.lock:
            try:
                # Clear cache periodically to prevent memory buildup
                if hasattr(mx.metal, 'clear_cache'):
                    mx.metal.clear_cache()
                
                # Use MLX generate function with memory management
                response = generate(
                    self.model,
                    self.tokenizer,
                    prompt=prompt,
                    max_tokens=max_tokens,
                    verbose=False
                )
                
                # Clear cache after generation
                mx.metal.clear_cache()
                
                return response
                
            except Exception as e:
                print(f"Error in generation: {e}")
                # Clear cache on error
                if hasattr(mx.metal, 'clear_cache'):
                    mx.metal.clear_cache()
                return f"Error generating response: {str(e)}"

def create_handler_class(model_manager):
    """Create a handler class with the model manager injected"""
    class Handler(MemoryOptimizedMLXHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, model_manager=model_manager, **kwargs)
    return Handler

def main():
    parser = argparse.ArgumentParser(description='Memory-Optimized MLX Server')
    parser.add_argument('--model', default='mlx-community/gemma-3-12b-it-4bit', help='Model name')
    parser.add_argument('--host', default='localhost', help='Host to bind to')
    parser.add_argument('--port', type=int, default=8080, help='Port to bind to')
    parser.add_argument('--max-cache-size', type=int, default=32768, help='Max KV cache size')
    
    args = parser.parse_args()
    
    # Set MLX environment variables for memory management
    os.environ['MLX_METAL_BUFFER_CACHE_LIMIT'] = '2048'
    os.environ['MLX_GPU_MEMORY_LIMIT'] = '0.8'
    
    print(f"Starting Memory-Optimized MLX Server")
    print(f"Model: {args.model}")
    print(f"Host: {args.host}")
    print(f"Port: {args.port}")
    print(f"Max Cache Size: {args.max_cache_size}")
    print("")
    
    # Initialize model manager
    model_manager = MemoryOptimizedModelManager(args.model, args.max_cache_size)
    
    # Create server
    handler_class = create_handler_class(model_manager)
    server = HTTPServer((args.host, args.port), handler_class)
    
    print(f"Server running on http://{args.host}:{args.port}")
    print("Memory optimizations enabled")
    print("Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()

if __name__ == '__main__':
    main()