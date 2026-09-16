import React from "react";
import { render, screen } from "@testing-library/react";
import App from "./App";

test("renders YouTube Clone header", () => {
  render(<App />);
  const header = screen.getByText(/YouTube Clone/i);
  expect(header).toBeInTheDocument();
});
