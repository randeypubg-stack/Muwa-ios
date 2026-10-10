import React from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { GlobalContextProviders } from "./components/_globalContextProviders";
import AdminPage from "./pages/admin";
import "./base.css";

createRoot(document.getElementById("root")!).render(
  <React.StrictMode><BrowserRouter><GlobalContextProviders><AdminPage /></GlobalContextProviders></BrowserRouter></React.StrictMode>,
);
