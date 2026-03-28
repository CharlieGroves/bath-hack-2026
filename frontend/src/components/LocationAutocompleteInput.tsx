import { useState } from 'react'
import { useGeoapifyAutocomplete, type GeoapifySuggestion } from '../hooks/useGeoapifyAutocomplete'
import './LocationAutocompleteInput.css'

type Theme = 'light' | 'dark'

interface Props {
  value: string
  onChange: (value: string) => void
  onEnter?: () => void
  onSelect?: (suggestion: GeoapifySuggestion) => void
  placeholder?: string
  inputClassName?: string
  wrapperClassName?: string
  theme?: Theme
}

export default function LocationAutocompleteInput({
  value,
  onChange,
  onEnter,
  onSelect,
  placeholder,
  inputClassName,
  wrapperClassName,
  theme = 'light',
}: Props) {
  const { suggestions, loading, enabled } = useGeoapifyAutocomplete(value)
  const [isOpen, setIsOpen] = useState(false)
  const [highlightedIndex, setHighlightedIndex] = useState(-1)

  const showPanel = enabled && isOpen && value.trim().length >= 3

  const activeIndex = suggestions.length === 0
    ? -1
    : highlightedIndex >= 0 && highlightedIndex < suggestions.length
      ? highlightedIndex
      : 0

  function applySuggestion(suggestion: GeoapifySuggestion) {
    onChange(suggestion.label)
    onSelect?.(suggestion)
    setIsOpen(false)
  }

  return (
    <div className={`lac-wrap ${wrapperClassName ?? ''}`.trim()}>
      <input
        className={inputClassName}
        type="text"
        autoComplete="off"
        placeholder={placeholder}
        value={value}
        onFocus={() => setIsOpen(true)}
        onBlur={() => {
          window.setTimeout(() => setIsOpen(false), 120)
        }}
        onChange={event => {
          onChange(event.target.value)
          setIsOpen(true)
        }}
        onKeyDown={event => {
          if (!showPanel) {
            if (event.key === 'Enter') onEnter?.()
            return
          }

          if (event.key === 'ArrowDown') {
            event.preventDefault()
            setHighlightedIndex(current => {
              if (suggestions.length === 0) return -1
              return current >= suggestions.length - 1 ? 0 : current + 1
            })
            return
          }

          if (event.key === 'ArrowUp') {
            event.preventDefault()
            setHighlightedIndex(current => {
              if (suggestions.length === 0) return -1
              return current <= 0 ? suggestions.length - 1 : current - 1
            })
            return
          }

          if (event.key === 'Escape') {
            setIsOpen(false)
            return
          }

          if (event.key === 'Enter') {
            if (activeIndex >= 0 && suggestions[activeIndex]) {
              event.preventDefault()
              applySuggestion(suggestions[activeIndex])
              return
            }

            onEnter?.()
          }
        }}
      />
      {showPanel && (
        <div className={`lac-panel lac-panel-${theme}`}>
          {loading && suggestions.length === 0 && (
            <div className="lac-status">Searching places...</div>
          )}
          {!loading && suggestions.length === 0 && (
            <div className="lac-status">No matching places found.</div>
          )}
          {suggestions.map((suggestion, index) => (
            <button
              key={suggestion.id}
              type="button"
              className={`lac-item ${activeIndex === index ? 'lac-item-active' : ''}`.trim()}
              onMouseDown={event => {
                event.preventDefault()
                applySuggestion(suggestion)
              }}
              onMouseEnter={() => setHighlightedIndex(index)}
            >
              <span className="lac-label">{suggestion.label}</span>
              {suggestion.secondaryLabel && (
                <span className="lac-meta">{suggestion.secondaryLabel}</span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
