import { createRoot } from "react-dom/client";
import "./index";
import "./demo.css";
import { DemoPage } from "./DemoPage";

createRoot(document.getElementById("root")!).render(<DemoPage />);
