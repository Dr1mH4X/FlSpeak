import React, { useState } from 'react';
import { LuImage } from 'react-icons/lu';

interface WorkspacePreviewProps {
  darkSrc?: string;
  lightSrc?: string;
}

export const WorkspacePreview: React.FC<WorkspacePreviewProps> = ({
  darkSrc = '/preview-dark.png',
  lightSrc = '/preview-light.png',
}) => {
  const [darkError, setDarkError] = useState(false);
  const [lightError, setLightError] = useState(false);

  const hasError = darkError && lightError;

  return (
    <div className="workspace-preview-stage">
      <div className="workspace-placeholder-frame">
        {!hasError ? (
          <>
            {!darkError && (
              <img
                src={darkSrc}
                alt="FlSpeak Workspace Preview (Dark)"
                className="workspace-placeholder-img workspace-placeholder-img-dark"
                onError={() => setDarkError(true)}
              />
            )}
            {!lightError && (
              <img
                src={lightSrc}
                alt="FlSpeak Workspace Preview (Light)"
                className="workspace-placeholder-img workspace-placeholder-img-light"
                onError={() => setLightError(true)}
              />
            )}
          </>
        ) : (
          <div className="workspace-placeholder-empty">
            <LuImage
              className="workspace-placeholder-icon"
              size={48}
              strokeWidth={1.5}
              aria-hidden="true"
            />
          </div>
        )}
      </div>
    </div>
  );
};
