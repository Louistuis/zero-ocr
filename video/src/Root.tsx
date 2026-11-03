import { Composition, Folder } from "remotion";
import { Showcase } from "./Showcase";
import { Intro } from "./scenes/Intro";
import { Demo } from "./scenes/Demo";
import { Outro } from "./scenes/Outro";

const size = { width: 1920, height: 1080, fps: 60 };

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="Showcase" component={Showcase} durationInFrames={600} {...size} />
    <Folder name="Scenes">
      <Composition id="Intro" component={Intro} durationInFrames={160} {...size} />
      <Composition id="Demo" component={Demo} durationInFrames={312} {...size} />
      <Composition id="Outro" component={Outro} durationInFrames={154} {...size} />
    </Folder>
  </>
);
