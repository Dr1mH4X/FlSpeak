import React, { useState } from 'react';

interface WorkspacePreviewProps {
  imageSrc?: string;
}

export const WorkspacePreview: React.FC<WorkspacePreviewProps> = ({
  imageSrc = '/preview.png',
}) => {
  const [hasError, setHasError] = useState(false);

  return (
    <div className="workspace-preview-stage">
      <div className="workspace-placeholder-frame">
        {!hasError ? (
          <img
            src={imageSrc}
            alt="FlSpeak Workspace Preview"
            className="workspace-placeholder-img"
            onError={() => setHasError(true)}
          />
        ) : (
          <div className="workspace-placeholder-empty">
            <svg
              className="workspace-placeholder-icon"
              viewBox="0 0 24 24"
              width="48"
              height="48"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
              <circle cx="8.5" cy="8.5" r="1.5" />
              <polyline points="21 15 16 10 5 21" />
            </svg>
          </div>
        )}
      </div>
    </div>
  );
};
