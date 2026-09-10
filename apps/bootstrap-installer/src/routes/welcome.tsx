import { useStore } from '@nanostores/react'
import { type CSSProperties, useState } from 'react'

import { HackeryButton } from '../components/hackery-button'
import { $platform, startInstall } from '../store'

/*
 * Welcome screen.
 *
 * Mirrors the desktop's chat intro (apps/desktop/src/components/chat/intro.tsx):
 *   - HERMES AGENT wordmark rendered in Collapse Bold, uppercase, tracked
 *   - mix-blend-plus-lighter so the type "glows" on the canvas
 *   - fit-text utility so the wordmark sizes itself to the column
 *
 * Below the hero is an optional "local model" section (Windows only) that
 * mirrors scripts/install-with-local-llm.ps1: point Hermes at an OpenAI-
 * compatible local endpoint, optionally installing Ollama first.
 */

export default function Welcome() {
  const platform = useStore($platform)
  const isWindows = platform === 'windows'

  const [configureLocalLlm, setConfigureLocalLlm] = useState(false)
  const [model, setModel] = useState('llama3.2:3b')
  const [baseUrl, setBaseUrl] = useState('http://localhost:11434/v1')
  const [skipOllama, setSkipOllama] = useState(false)

  function handleInstall() {
    void startInstall({ configureLocalLlm, model, baseUrl, skipOllama })
  }

  return (
    <div className="hermes-fade-in flex h-full flex-col overflow-y-auto px-12 py-10">
      <div className="m-auto flex w-full flex-col items-center gap-7">
        {/* Hero — same recipe the desktop's chat/intro.tsx uses */}
        <div className="w-full max-w-2xl min-w-0 text-center">
          <p
            className="fit-text mx-auto mb-4 w-full font-['Collapse'] font-bold uppercase leading-[0.9] tracking-[0.08em] text-midground mix-blend-plus-lighter dark:text-foreground/90"
            style={
              {
                '--fit-text-line-height': '0.9',
                '--fit-text-max': '6rem',
                '--fit-text-min': '2.5rem'
              } as CSSProperties
            }
          >
            <span>
              <span>SHANI AGENT</span>
            </span>
            <span aria-hidden="true">SHANI AGENT</span>
          </p>

          <p className="m-0 text-center text-base leading-normal tracking-tight text-muted-foreground">
            The agent that grows with you. We&rsquo;ll set things up in the
            background &mdash; takes a few minutes.
          </p>
        </div>

        {isWindows && (
          <div className="flex w-full max-w-md flex-col gap-3 text-left">
            <label className="flex cursor-pointer select-none items-center gap-2.5 text-sm text-muted-foreground">
              <input
                checked={configureLocalLlm}
                className="h-4 w-4 cursor-pointer"
                onChange={(e) => setConfigureLocalLlm(e.target.checked)}
                type="checkbox"
              />
              <span>Use a local model (Ollama, LM Studio, vLLM&hellip;)</span>
            </label>

            {configureLocalLlm && (
              <div className="hermes-fade-in flex flex-col gap-3 rounded-lg border border-(--stroke-nous) p-4">
                <Field label="Model" onChange={setModel} placeholder="llama3.2:3b" value={model} />
                <Field
                  label="Base URL"
                  onChange={setBaseUrl}
                  placeholder="http://localhost:11434/v1"
                  value={baseUrl}
                />
                <label className="flex cursor-pointer select-none items-center gap-2.5 text-sm text-muted-foreground">
                  <input
                    checked={skipOllama}
                    className="h-4 w-4 cursor-pointer"
                    onChange={(e) => setSkipOllama(e.target.checked)}
                    type="checkbox"
                  />
                  <span>Skip Ollama install (I already have a server running)</span>
                </label>
              </div>
            )}
          </div>
        )}

        <HackeryButton label="Install" onClick={handleInstall} />
      </div>
    </div>
  )
}

function Field({
  label,
  value,
  onChange,
  placeholder
}: {
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string
}) {
  return (
    <label className="flex flex-col gap-1.5 text-sm">
      <span className="text-xs uppercase tracking-wide text-muted-foreground">{label}</span>
      <input
        className="w-full rounded-md border border-(--stroke-nous) bg-(--ui-bg-tertiary) px-3 py-2 font-mono text-sm text-foreground outline-none transition-colors placeholder:text-muted-foreground/50 focus:border-primary/60"
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        spellCheck={false}
        value={value}
      />
    </label>
  )
}
